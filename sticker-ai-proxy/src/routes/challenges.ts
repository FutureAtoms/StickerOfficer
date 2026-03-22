import { Hono } from 'hono';
import type { Env } from '../index';
import { requireAuth, requireTerms } from '../middleware/auth';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type ChallengeRow = {
  id: string;
  title: string;
  description: string | null;
  theme: string;
  status: string;
  starts_at: string;
  voting_at: string;
  ends_at: string;
  created_at: string;
};

type SubmissionRow = {
  id: string;
  challenge_id: string;
  device_id: string;
  sticker_r2_key: string;
  vote_count: number;
  is_removed: number | boolean;
  created_at: string;
  author_public_id: string;
};

const challenges = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

/**
 * GET /
 * List challenges, optionally filtered by status.
 * Query: ?status=active (optional; default: all)
 */
challenges.get('/', async (c) => {
  const status = c.req.query('status');

  let stmt;
  if (status) {
    stmt = c.env.DB.prepare(
      'SELECT * FROM challenges WHERE status = ? ORDER BY created_at DESC',
    ).bind(status);
  } else {
    stmt = c.env.DB.prepare(
      'SELECT * FROM challenges ORDER BY created_at DESC',
    );
  }

  const { results } = await stmt.all<ChallengeRow>();
  return c.json({ challenges: results });
});

/**
 * POST /:id/submit
 * Submit a sticker to an active challenge.
 * Requires auth + terms.
 * Body: { sticker_r2_key: string }
 */
challenges.post('/:id/submit', requireAuth, requireTerms, async (c) => {
  const challengeId = c.req.param('id');
  const deviceId = c.get('deviceId');

  let body: { sticker_r2_key?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const stickerR2Key = body.sticker_r2_key;
  if (!stickerR2Key || typeof stickerR2Key !== 'string' || stickerR2Key.trim().length === 0) {
    return c.json({ error: 'sticker_r2_key is required' }, 400);
  }

  // Verify challenge exists and is active
  const challenge = await c.env.DB.prepare(
    'SELECT status FROM challenges WHERE id = ?',
  )
    .bind(challengeId)
    .first<{ status: string }>();

  if (!challenge) {
    return c.json({ error: 'Challenge not found' }, 404);
  }

  if (challenge.status !== 'active') {
    return c.json({ error: 'Challenge is not active' }, 409);
  }

  // Generate submission ID
  const submissionId = `sub_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`;

  await c.env.DB.prepare(
    'INSERT INTO challenge_submissions (id, challenge_id, device_id, sticker_r2_key) VALUES (?, ?, ?, ?)',
  )
    .bind(submissionId, challengeId, deviceId, stickerR2Key)
    .run();

  const submission = await c.env.DB.prepare(
    'SELECT * FROM challenge_submissions WHERE id = ?',
  )
    .bind(submissionId)
    .first();

  return c.json({ submission }, 201);
});

/**
 * POST /:id/vote
 * Vote on a submission in a challenge that is in 'voting' status.
 * Reddit-style: one vote per device per submission; can vote on multiple submissions.
 * Requires auth.
 * Body: { submission_id: string }
 */
challenges.post('/:id/vote', requireAuth, async (c) => {
  const challengeId = c.req.param('id');
  const deviceId = c.get('deviceId');

  let body: { submission_id?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const submissionId = body.submission_id;
  if (!submissionId || typeof submissionId !== 'string' || submissionId.trim().length === 0) {
    return c.json({ error: 'submission_id is required' }, 400);
  }

  // Verify challenge exists and is in voting status
  const challenge = await c.env.DB.prepare(
    'SELECT status FROM challenges WHERE id = ?',
  )
    .bind(challengeId)
    .first<{ status: string }>();

  if (!challenge) {
    return c.json({ error: 'Challenge not found' }, 404);
  }

  if (challenge.status !== 'voting') {
    return c.json({ error: 'Challenge is not in voting phase' }, 409);
  }

  // Verify submission belongs to this challenge
  const submission = await c.env.DB.prepare(
    'SELECT id, vote_count FROM challenge_submissions WHERE id = ? AND challenge_id = ?',
  )
    .bind(submissionId, challengeId)
    .first<{ id: string; vote_count: number }>();

  if (!submission) {
    return c.json({ error: 'Submission not found in this challenge' }, 404);
  }

  // INSERT OR IGNORE — if already voted, this is a no-op
  const voteResult = await c.env.DB.prepare(
    'INSERT OR IGNORE INTO challenge_votes (device_id, submission_id) VALUES (?, ?)',
  )
    .bind(deviceId, submissionId)
    .run();

  const voted = (voteResult.meta?.changes ?? 0) > 0;

  if (voted) {
    // Increment vote_count on the submission
    await c.env.DB.prepare(
      'UPDATE challenge_submissions SET vote_count = vote_count + 1 WHERE id = ?',
    )
      .bind(submissionId)
      .run();
  }

  // Fetch updated vote count
  const updated = await c.env.DB.prepare(
    'SELECT vote_count FROM challenge_submissions WHERE id = ?',
  )
    .bind(submissionId)
    .first<{ vote_count: number }>();

  return c.json({ voted, vote_count: updated?.vote_count ?? submission.vote_count });
});

/**
 * GET /:id/submissions
 * List submissions for a challenge with vote counts.
 * Joins with devices for author public_id.
 * Excludes removed submissions.
 * Ordered by vote_count DESC.
 */
challenges.get('/:id/submissions', async (c) => {
  const challengeId = c.req.param('id');

  const { results } = await c.env.DB.prepare(
    `SELECT cs.id, cs.challenge_id, cs.device_id, cs.sticker_r2_key,
            cs.vote_count, cs.created_at, d.public_id AS author_public_id
     FROM challenge_submissions cs
     JOIN devices d ON cs.device_id = d.device_id
     WHERE cs.challenge_id = ? AND cs.is_removed = FALSE
     ORDER BY cs.vote_count DESC`,
  )
    .bind(challengeId)
    .all<SubmissionRow>();

  return c.json({ submissions: results });
});

export default challenges;
