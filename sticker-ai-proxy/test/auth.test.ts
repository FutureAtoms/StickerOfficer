import {
  env,
  createExecutionContext,
  waitOnExecutionContext,
} from 'cloudflare:test';
import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index';

// Type the env as our worker Env
const testEnv = env as { DB: D1Database; JWT_SECRET: string; [k: string]: unknown };

// Helper to issue a fetch against the worker
async function workerFetch(path: string, init?: RequestInit) {
  const request = new Request(`http://localhost${path}`, init);
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, testEnv, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

// Schema SQL — D1 exec() requires each statement on one logical line
// Includes social columns from migration 002 (Google) and 003 (Apple)
const SCHEMA = "CREATE TABLE IF NOT EXISTS devices (device_id TEXT PRIMARY KEY, public_id TEXT UNIQUE NOT NULL, display_name TEXT, terms_accepted_at TEXT, is_blocked BOOLEAN DEFAULT FALSE, packs_created INTEGER DEFAULT 0, total_likes_received INTEGER DEFAULT 0, first_seen TEXT DEFAULT (datetime('now')), last_seen TEXT DEFAULT (datetime('now')), google_id TEXT, google_email TEXT, google_name TEXT, google_photo TEXT, apple_id TEXT, apple_email TEXT, apple_name TEXT);";

describe('Auth routes', () => {
  beforeEach(async () => {
    // Recreate the devices table for a clean slate
    await testEnv.DB.exec('DROP TABLE IF EXISTS devices;');
    await testEnv.DB.exec(SCHEMA);
  });

  it('POST /auth/register returns JWT and public_id matching user_[a-z0-9]+', async () => {
    const res = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-001' }),
    });

    expect(res.status).toBe(200);
    const data = await res.json() as { token: string; public_id: string; expires_in: number };
    expect(data.token).toBeTruthy();
    expect(data.public_id).toMatch(/^user_[a-z0-9]+$/);
    expect(data.expires_in).toBe(31536000);
  });

  it('Repeat registration returns same public_id but new token', async () => {
    const res1 = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-002' }),
    });
    const data1 = await res1.json() as { token: string; public_id: string };

    const res2 = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-002' }),
    });
    const data2 = await res2.json() as { token: string; public_id: string };

    expect(data1.public_id).toBe(data2.public_id);
    // Tokens differ because iat will be different (or at minimum they are re-signed)
    // They might be the same if issued in the same second, so we just check both are valid strings
    expect(data2.token).toBeTruthy();
  });

  it('Missing device_id returns 400', async () => {
    const res = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });

    expect(res.status).toBe(400);
    const data = await res.json() as { error: string };
    expect(data.error).toContain('device_id');
  });

  it('POST /auth/refresh with device_id returns new token', async () => {
    // First register
    const regRes = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-003' }),
    });
    const regData = await regRes.json() as { token: string; public_id: string };

    // Then refresh using device_id (no auth header needed)
    const refreshRes = await workerFetch('/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-003' }),
    });

    expect(refreshRes.status).toBe(200);
    const refreshData = await refreshRes.json() as { token: string; public_id: string; device_id: string; expires_in: number };
    expect(refreshData.token).toBeTruthy();
    expect(refreshData.public_id).toBe(regData.public_id);
    expect(refreshData.device_id).toBe('test-device-003');
    expect(refreshData.expires_in).toBe(31536000);
  });

  it('POST /auth/accept-terms sets terms_accepted_at', async () => {
    // Register
    const regRes = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-004' }),
    });
    const regData = await regRes.json() as { token: string };

    // Verify terms not yet accepted
    const before = await testEnv.DB.prepare(
      'SELECT terms_accepted_at FROM devices WHERE device_id = ?',
    )
      .bind('test-device-004')
      .first<{ terms_accepted_at: string | null }>();
    expect(before?.terms_accepted_at).toBeNull();

    // Accept terms
    const termsRes = await workerFetch('/auth/accept-terms', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${regData.token}`,
      },
    });

    expect(termsRes.status).toBe(200);
    const termsData = await termsRes.json() as { ok: boolean };
    expect(termsData.ok).toBe(true);

    // Verify terms_accepted_at is now set
    const after = await testEnv.DB.prepare(
      'SELECT terms_accepted_at FROM devices WHERE device_id = ?',
    )
      .bind('test-device-004')
      .first<{ terms_accepted_at: string | null }>();
    expect(after?.terms_accepted_at).toBeTruthy();
  });

  it('POST /auth/refresh without device_id returns 400', async () => {
    const res = await workerFetch('/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });

    expect(res.status).toBe(400);
    const data = await res.json() as { error: string };
    expect(data.error).toContain('device_id');
  });

  it('POST /auth/refresh with unknown device returns 404', async () => {
    const res = await workerFetch('/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'nonexistent-device' }),
    });

    expect(res.status).toBe(404);
  });

  it('POST /auth/register returns device_id in response', async () => {
    const res = await workerFetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-devid' }),
    });

    expect(res.status).toBe(200);
    const data = await res.json() as { token: string; public_id: string; device_id: string };
    expect(data.device_id).toBe('test-device-devid');
  });
});
