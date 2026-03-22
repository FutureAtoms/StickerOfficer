import {
  env,
  createExecutionContext,
  waitOnExecutionContext,
} from 'cloudflare:test';
import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index';

const testEnv = env as { DB: D1Database; JWT_SECRET: string; [k: string]: unknown };

async function workerFetch(path: string, init?: RequestInit) {
  const request = new Request(`http://localhost${path}`, init);
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, testEnv, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

// Schema — each table as a single logical line for D1 exec()
const DEVICES_SCHEMA =
  "CREATE TABLE IF NOT EXISTS devices (device_id TEXT PRIMARY KEY, public_id TEXT UNIQUE NOT NULL, display_name TEXT, terms_accepted_at TEXT, is_blocked BOOLEAN DEFAULT FALSE, packs_created INTEGER DEFAULT 0, total_likes_received INTEGER DEFAULT 0, first_seen TEXT DEFAULT (datetime('now')), last_seen TEXT DEFAULT (datetime('now')));";

const PACKS_SCHEMA =
  "CREATE TABLE IF NOT EXISTS packs (id TEXT PRIMARY KEY, name TEXT NOT NULL, author_device_id TEXT NOT NULL REFERENCES devices(device_id), category TEXT, sticker_count INTEGER DEFAULT 0, like_count INTEGER DEFAULT 0, download_count INTEGER DEFAULT 0, is_public BOOLEAN DEFAULT FALSE, is_removed BOOLEAN DEFAULT FALSE, tags TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')));";

const STICKERS_SCHEMA =
  "CREATE TABLE IF NOT EXISTS stickers (id TEXT PRIMARY KEY, pack_id TEXT NOT NULL REFERENCES packs(id), r2_key TEXT NOT NULL, position INTEGER DEFAULT 0);";

const LIKES_SCHEMA =
  "CREATE TABLE IF NOT EXISTS likes (device_id TEXT NOT NULL REFERENCES devices(device_id), pack_id TEXT NOT NULL REFERENCES packs(id), created_at TEXT DEFAULT (datetime('now')), PRIMARY KEY (device_id, pack_id));";

const DOWNLOADS_SCHEMA =
  "CREATE TABLE IF NOT EXISTS downloads (device_id TEXT NOT NULL REFERENCES devices(device_id), pack_id TEXT NOT NULL REFERENCES packs(id), created_at TEXT DEFAULT (datetime('now')), PRIMARY KEY (device_id, pack_id));";

/** Register a device, accept terms, and return the token + public_id */
async function registerAndAcceptTerms(deviceId: string) {
  const regRes = await workerFetch('/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ device_id: deviceId }),
  });
  const regData = (await regRes.json()) as { token: string; public_id: string };

  // Accept terms so requireTerms middleware passes
  await workerFetch('/auth/accept-terms', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${regData.token}`,
    },
  });

  return regData;
}

/** Publish a pack and return the response data */
async function publishPack(
  token: string,
  overrides?: { name?: string; category?: string; tags?: string[]; stickers?: { r2_key: string }[] },
) {
  const body = {
    name: overrides?.name ?? 'Test Pack',
    category: overrides?.category ?? 'funny',
    tags: overrides?.tags ?? ['test', 'demo'],
    stickers: overrides?.stickers ?? [{ r2_key: 'stickers/img1.webp' }, { r2_key: 'stickers/img2.webp' }],
  };

  const res = await workerFetch('/packs', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  return { res, data: (await res.json()) as Record<string, unknown> };
}

describe('Pack routes', () => {
  beforeEach(async () => {
    // Drop and recreate all relevant tables
    await testEnv.DB.exec('DROP TABLE IF EXISTS downloads;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS likes;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS stickers;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS packs;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS devices;');
    await testEnv.DB.exec(DEVICES_SCHEMA);
    await testEnv.DB.exec(PACKS_SCHEMA);
    await testEnv.DB.exec(STICKERS_SCHEMA);
    await testEnv.DB.exec(LIKES_SCHEMA);
    await testEnv.DB.exec(DOWNLOADS_SCHEMA);
  });

  // ---- Publish ----

  it('POST /packs publishes a pack and returns 201', async () => {
    const { token } = await registerAndAcceptTerms('device-pack-1');
    const { res, data } = await publishPack(token);

    expect(res.status).toBe(201);
    expect(data.id).toBeTruthy();
    expect(data.name).toBe('Test Pack');
    expect(data.category).toBe('funny');
    expect(data.sticker_count).toBe(2);
    expect(data.like_count).toBe(0);
    expect(data.download_count).toBe(0);
    expect(data.is_public).toBe(true);
    expect(data.tags).toEqual(['test', 'demo']);
  });

  it('POST /packs increments packs_created on device', async () => {
    const { token } = await registerAndAcceptTerms('device-pack-2');
    await publishPack(token);
    await publishPack(token, { name: 'Pack Two' });

    const device = await testEnv.DB.prepare(
      'SELECT packs_created FROM devices WHERE device_id = ?',
    )
      .bind('device-pack-2')
      .first<{ packs_created: number }>();

    expect(device?.packs_created).toBe(2);
  });

  it('POST /packs inserts stickers into stickers table', async () => {
    const { token } = await registerAndAcceptTerms('device-pack-3');
    const { data } = await publishPack(token);

    const { results } = await testEnv.DB.prepare(
      'SELECT r2_key, position FROM stickers WHERE pack_id = ? ORDER BY position',
    )
      .bind(data.id as string)
      .all();

    expect(results.length).toBe(2);
    expect(results[0].r2_key).toBe('stickers/img1.webp');
    expect(results[0].position).toBe(0);
    expect(results[1].r2_key).toBe('stickers/img2.webp');
    expect(results[1].position).toBe(1);
  });

  it('POST /packs rejects missing name', async () => {
    const { token } = await registerAndAcceptTerms('device-pack-4');
    const res = await workerFetch('/packs', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ stickers: [{ r2_key: 'a.webp' }] }),
    });

    expect(res.status).toBe(400);
    const data = (await res.json()) as { error: string };
    expect(data.error).toContain('name');
  });

  it('POST /packs rejects empty stickers', async () => {
    const { token } = await registerAndAcceptTerms('device-pack-5');
    const res = await workerFetch('/packs', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ name: 'No Stickers', stickers: [] }),
    });

    expect(res.status).toBe(400);
    const data = (await res.json()) as { error: string };
    expect(data.error).toContain('stickers');
  });

  it('POST /packs requires terms acceptance', async () => {
    // Register but do NOT accept terms
    const regRes = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'device-no-terms' }),
    });
    const { token } = (await regRes.json()) as { token: string };

    const res = await workerFetch('/packs', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        name: 'Blocked',
        stickers: [{ r2_key: 'a.webp' }],
      }),
    });

    expect(res.status).toBe(403);
  });

  // ---- Like / Unlike ----

  it('POST /packs/:id/like toggles like on and off', async () => {
    const { token } = await registerAndAcceptTerms('device-like-1');
    const { data: pack } = await publishPack(token);
    const packId = pack.id as string;

    // First like
    const likeRes1 = await workerFetch(`/packs/${packId}/like`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(likeRes1.status).toBe(200);
    const likeData1 = (await likeRes1.json()) as { liked: boolean; like_count: number };
    expect(likeData1.liked).toBe(true);
    expect(likeData1.like_count).toBe(1);

    // Unlike (toggle off)
    const likeRes2 = await workerFetch(`/packs/${packId}/like`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(likeRes2.status).toBe(200);
    const likeData2 = (await likeRes2.json()) as { liked: boolean; like_count: number };
    expect(likeData2.liked).toBe(false);
    expect(likeData2.like_count).toBe(0);

    // Like again
    const likeRes3 = await workerFetch(`/packs/${packId}/like`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    const likeData3 = (await likeRes3.json()) as { liked: boolean; like_count: number };
    expect(likeData3.liked).toBe(true);
    expect(likeData3.like_count).toBe(1);
  });

  it('POST /packs/:id/like returns 404 for non-existent pack', async () => {
    const { token } = await registerAndAcceptTerms('device-like-2');
    const res = await workerFetch('/packs/non-existent-id/like', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(404);
  });

  // ---- Download ----

  it('POST /packs/:id/download tracks download and is idempotent', async () => {
    const { token } = await registerAndAcceptTerms('device-dl-1');
    const { data: pack } = await publishPack(token);
    const packId = pack.id as string;

    // First download
    const dlRes1 = await workerFetch(`/packs/${packId}/download`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(dlRes1.status).toBe(200);
    const dlData1 = (await dlRes1.json()) as { downloaded: boolean; download_count: number };
    expect(dlData1.downloaded).toBe(true);
    expect(dlData1.download_count).toBe(1);

    // Second download — idempotent, count should NOT increase
    const dlRes2 = await workerFetch(`/packs/${packId}/download`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(dlRes2.status).toBe(200);
    const dlData2 = (await dlRes2.json()) as { downloaded: boolean; download_count: number };
    expect(dlData2.downloaded).toBe(true);
    expect(dlData2.download_count).toBe(1);

    // Verify DB has only 1 download record
    const count = await testEnv.DB.prepare(
      'SELECT COUNT(*) as cnt FROM downloads WHERE pack_id = ?',
    )
      .bind(packId)
      .first<{ cnt: number }>();
    expect(count?.cnt).toBe(1);
  });

  it('POST /packs/:id/download returns 404 for non-existent pack', async () => {
    const { token } = await registerAndAcceptTerms('device-dl-2');
    const res = await workerFetch('/packs/non-existent-id/download', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(404);
  });

  // ---- List by author ----

  it('GET /packs?author=<publicId> lists packs by author', async () => {
    const { token, public_id } = await registerAndAcceptTerms('device-list-1');

    // Publish 2 packs
    await publishPack(token, { name: 'Pack Alpha' });
    await publishPack(token, { name: 'Pack Beta' });

    const res = await workerFetch(`/packs?author=${public_id}`);
    expect(res.status).toBe(200);
    const data = (await res.json()) as { packs: Record<string, unknown>[]; total: number };
    expect(data.total).toBe(2);
    expect(data.packs.length).toBe(2);
    // Most recent first
    expect(data.packs[0].name).toBe('Pack Beta');
    expect(data.packs[1].name).toBe('Pack Alpha');
  });

  it('GET /packs?author=<publicId> excludes removed packs', async () => {
    const { token, public_id } = await registerAndAcceptTerms('device-list-2');
    const { data: pack } = await publishPack(token, { name: 'Removed Pack' });

    // Mark pack as removed directly in DB
    await testEnv.DB.prepare('UPDATE packs SET is_removed = TRUE WHERE id = ?')
      .bind(pack.id as string)
      .run();

    const res = await workerFetch(`/packs?author=${public_id}`);
    const data = (await res.json()) as { packs: Record<string, unknown>[]; total: number };
    expect(data.total).toBe(0);
    expect(data.packs.length).toBe(0);
  });

  it('GET /packs?author=unknown returns empty list', async () => {
    const res = await workerFetch('/packs?author=user_nonexistent');
    expect(res.status).toBe(200);
    const data = (await res.json()) as { packs: Record<string, unknown>[]; total: number };
    expect(data.packs).toEqual([]);
    expect(data.total).toBe(0);
  });

  it('GET /packs without author param returns 400', async () => {
    const res = await workerFetch('/packs');
    expect(res.status).toBe(400);
    const data = (await res.json()) as { error: string };
    expect(data.error).toContain('author');
  });
});
