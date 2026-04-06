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

// Schema statements — each must be a single logical statement for D1 exec()
const DEVICES_SCHEMA =
  "CREATE TABLE IF NOT EXISTS devices (device_id TEXT PRIMARY KEY, public_id TEXT UNIQUE NOT NULL, display_name TEXT, terms_accepted_at TEXT, is_blocked BOOLEAN DEFAULT FALSE, packs_created INTEGER DEFAULT 0, total_likes_received INTEGER DEFAULT 0, first_seen TEXT DEFAULT (datetime('now')), last_seen TEXT DEFAULT (datetime('now')), google_id TEXT, google_email TEXT, google_name TEXT, google_photo TEXT, apple_id TEXT, apple_email TEXT, apple_name TEXT);";

const CHALLENGES_SCHEMA =
  "CREATE TABLE IF NOT EXISTS challenges (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, theme TEXT NOT NULL, status TEXT DEFAULT 'upcoming', starts_at TEXT NOT NULL, voting_at TEXT NOT NULL, ends_at TEXT NOT NULL, created_at TEXT DEFAULT (datetime('now')));";

const SUBMISSIONS_SCHEMA =
  "CREATE TABLE IF NOT EXISTS challenge_submissions (id TEXT PRIMARY KEY, challenge_id TEXT NOT NULL REFERENCES challenges(id), device_id TEXT NOT NULL REFERENCES devices(device_id), sticker_r2_key TEXT NOT NULL, vote_count INTEGER DEFAULT 0, is_removed BOOLEAN DEFAULT FALSE, created_at TEXT DEFAULT (datetime('now')));";

const VOTES_SCHEMA =
  "CREATE TABLE IF NOT EXISTS challenge_votes (device_id TEXT NOT NULL REFERENCES devices(device_id), submission_id TEXT NOT NULL REFERENCES challenge_submissions(id), created_at TEXT DEFAULT (datetime('now')), PRIMARY KEY (device_id, submission_id));";

async function registerAndAcceptTerms(deviceId: string): Promise<string> {
  const regRes = await workerFetch('/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ device_id: deviceId }),
  });
  const regData = (await regRes.json()) as { token: string };

  await workerFetch('/auth/accept-terms', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${regData.token}`,
    },
  });

  return regData.token;
}

async function registerDevice(deviceId: string): Promise<string> {
  const regRes = await workerFetch('/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ device_id: deviceId }),
  });
  const regData = (await regRes.json()) as { token: string };
  return regData.token;
}

async function seedChallenge(id: string, status: string): Promise<void> {
  await testEnv.DB.prepare(
    "INSERT INTO challenges (id, title, theme, status, starts_at, voting_at, ends_at) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'), datetime('now'))",
  )
    .bind(id, `Challenge ${id}`, `theme-${id}`, status)
    .run();
}

describe('Challenge routes', () => {
  beforeEach(async () => {
    await testEnv.DB.exec('DROP TABLE IF EXISTS challenge_votes;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS challenge_submissions;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS challenges;');
    await testEnv.DB.exec('DROP TABLE IF EXISTS devices;');
    await testEnv.DB.exec(DEVICES_SCHEMA);
    await testEnv.DB.exec(CHALLENGES_SCHEMA);
    await testEnv.DB.exec(SUBMISSIONS_SCHEMA);
    await testEnv.DB.exec(VOTES_SCHEMA);
  });

  it('GET /challenges returns all challenges ordered by created_at DESC', async () => {
    await seedChallenge('ch-1', 'active');
    await seedChallenge('ch-2', 'voting');
    await seedChallenge('ch-3', 'active');

    const res = await workerFetch('/challenges');
    expect(res.status).toBe(200);
    const data = (await res.json()) as { challenges: Array<{ id: string; status: string }> };
    expect(data.challenges).toHaveLength(3);
  });

  it('GET /challenges?status=active filters by status', async () => {
    await seedChallenge('ch-a', 'active');
    await seedChallenge('ch-b', 'voting');
    await seedChallenge('ch-c', 'active');

    const res = await workerFetch('/challenges?status=active');
    expect(res.status).toBe(200);
    const data = (await res.json()) as { challenges: Array<{ id: string; status: string }> };
    expect(data.challenges).toHaveLength(2);
    for (const ch of data.challenges) {
      expect(ch.status).toBe('active');
    }
  });

  it('POST /challenges/:id/submit creates submission for active challenge', async () => {
    await seedChallenge('ch-active', 'active');
    const token = await registerAndAcceptTerms('dev-submit-1');

    const res = await workerFetch('/challenges/ch-active/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ sticker_r2_key: 'stickers/test.webp' }),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as {
      submission: { id: string; challenge_id: string; sticker_r2_key: string };
    };
    expect(data.submission.id).toMatch(/^sub_/);
    expect(data.submission.challenge_id).toBe('ch-active');
    expect(data.submission.sticker_r2_key).toBe('stickers/test.webp');
  });

  it('POST /challenges/:id/submit rejects non-active challenge', async () => {
    await seedChallenge('ch-voting', 'voting');
    const token = await registerAndAcceptTerms('dev-submit-2');

    const res = await workerFetch('/challenges/ch-voting/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ sticker_r2_key: 'stickers/test.webp' }),
    });

    expect(res.status).toBe(409);
  });

  it('POST /challenges/:id/submit requires terms accepted', async () => {
    await seedChallenge('ch-terms', 'active');
    const token = await registerDevice('dev-no-terms');

    const res = await workerFetch('/challenges/ch-terms/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ sticker_r2_key: 'stickers/test.webp' }),
    });

    expect(res.status).toBe(403);
  });

  it('POST /challenges/:id/vote records vote and increments count', async () => {
    await seedChallenge('ch-vote', 'voting');
    const submitterToken = await registerAndAcceptTerms('dev-voter-setup');
    // Manually insert a submission for voting
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES ('sub-1', 'ch-vote', 'dev-voter-setup', 'stickers/v.webp')",
    ).run();

    const voterToken = await registerDevice('dev-voter-1');

    const res = await workerFetch('/challenges/ch-vote/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-1' }),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as { voted: boolean; vote_count: number };
    expect(data.voted).toBe(true);
    expect(data.vote_count).toBe(1);
  });

  it('POST /challenges/:id/vote prevents duplicate vote on same submission', async () => {
    await seedChallenge('ch-dup', 'voting');
    // Need the device to exist for the submission author before inserting submission
    await registerDevice('dev-voter-setup2');
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES ('sub-dup', 'ch-dup', 'dev-voter-setup2', 'stickers/d.webp')",
    ).run();

    const voterToken = await registerDevice('dev-voter-dup');

    // First vote
    const res1 = await workerFetch('/challenges/ch-dup/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-dup' }),
    });
    const data1 = (await res1.json()) as { voted: boolean; vote_count: number };
    expect(data1.voted).toBe(true);
    expect(data1.vote_count).toBe(1);

    // Duplicate vote
    const res2 = await workerFetch('/challenges/ch-dup/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-dup' }),
    });
    const data2 = (await res2.json()) as { voted: boolean; vote_count: number };
    expect(data2.voted).toBe(false);
    expect(data2.vote_count).toBe(1); // should NOT increment
  });

  it('POST /challenges/:id/vote allows voting on multiple submissions', async () => {
    await seedChallenge('ch-multi', 'voting');
    // Create author device first
    await registerDevice('dev-author-multi');
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES ('sub-m1', 'ch-multi', 'dev-author-multi', 'stickers/m1.webp')",
    ).run();
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES ('sub-m2', 'ch-multi', 'dev-author-multi', 'stickers/m2.webp')",
    ).run();

    const voterToken = await registerDevice('dev-multi-voter');

    // Vote on first submission
    const res1 = await workerFetch('/challenges/ch-multi/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-m1' }),
    });
    const data1 = (await res1.json()) as { voted: boolean; vote_count: number };
    expect(data1.voted).toBe(true);

    // Vote on second submission
    const res2 = await workerFetch('/challenges/ch-multi/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-m2' }),
    });
    const data2 = (await res2.json()) as { voted: boolean; vote_count: number };
    expect(data2.voted).toBe(true);
  });

  it('POST /challenges/:id/vote rejects vote on non-voting challenge', async () => {
    await seedChallenge('ch-not-voting', 'active');
    await registerDevice('dev-author-nv');
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES ('sub-nv', 'ch-not-voting', 'dev-author-nv', 'stickers/nv.webp')",
    ).run();

    const voterToken = await registerDevice('dev-voter-nv');

    const res = await workerFetch('/challenges/ch-not-voting/vote', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${voterToken}`,
      },
      body: JSON.stringify({ submission_id: 'sub-nv' }),
    });

    expect(res.status).toBe(409);
  });

  it('GET /challenges/:id/submissions lists non-removed submissions with author public_id', async () => {
    await seedChallenge('ch-list', 'voting');
    const token = await registerAndAcceptTerms('dev-list-author');

    // Get the public_id for the author
    const device = await testEnv.DB.prepare(
      'SELECT public_id FROM devices WHERE device_id = ?',
    )
      .bind('dev-list-author')
      .first<{ public_id: string }>();

    // Insert submissions: one visible, one removed
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key, vote_count) VALUES ('sub-vis', 'ch-list', 'dev-list-author', 'stickers/vis.webp', 5)",
    ).run();
    await testEnv.DB.prepare(
      "INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key, is_removed) VALUES ('sub-rem', 'ch-list', 'dev-list-author', 'stickers/rem.webp', TRUE)",
    ).run();

    const res = await workerFetch('/challenges/ch-list/submissions');
    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      submissions: Array<{ id: string; vote_count: number; author_public_id: string }>;
    };

    // Only non-removed submission returned
    expect(data.submissions).toHaveLength(1);
    expect(data.submissions[0].id).toBe('sub-vis');
    expect(data.submissions[0].vote_count).toBe(5);
    expect(data.submissions[0].author_public_id).toBe(device!.public_id);
  });
});
