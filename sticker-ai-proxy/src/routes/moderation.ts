import { Hono } from 'hono';
import type { Env } from '../index';
import { requireAuth } from '../middleware/auth';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type ModerationEnv = { Bindings: Env; Variables: AuthVariables };

export const moderation = new Hono<ModerationEnv>();

// ---------------------------------------------------------------------------
// User routes (requireAuth)
// ---------------------------------------------------------------------------

/**
 * POST /report — Report content
 * Body: { target_type, target_id, reason, details? }
 */
moderation.post('/report', requireAuth, async (c) => {
  let body: {
    target_type?: string;
    target_id?: string;
    reason?: string;
    details?: string;
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { target_type, target_id, reason, details } = body;

  const validTargetTypes = ['pack', 'sticker', 'submission', 'user'];
  if (!target_type || !validTargetTypes.includes(target_type)) {
    return c.json({ error: 'target_type must be one of: pack, sticker, submission, user' }, 400);
  }

  if (!target_id || typeof target_id !== 'string' || target_id.trim().length === 0) {
    return c.json({ error: 'target_id is required' }, 400);
  }

  const validReasons = ['inappropriate', 'copyright', 'spam', 'harassment', 'other'];
  if (!reason || !validReasons.includes(reason)) {
    return c.json({ error: 'reason must be one of: inappropriate, copyright, spam, harassment, other' }, 400);
  }

  const reportId = crypto.randomUUID();
  const deviceId = c.get('deviceId');

  await c.env.DB.prepare(
    `INSERT INTO reports (id, reporter_device_id, target_type, target_id, reason, details, status)
     VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
  )
    .bind(reportId, deviceId, target_type, target_id.trim(), reason, details ?? null)
    .run();

  return c.json({ id: reportId }, 201);
});

/**
 * POST /block/:publicId — Block a user
 */
moderation.post('/block/:publicId', requireAuth, async (c) => {
  const targetPublicId = c.req.param('publicId');
  const blockerDeviceId = c.get('deviceId');

  // Resolve publicId to device_id
  const target = await c.env.DB.prepare(
    'SELECT device_id FROM devices WHERE public_id = ?',
  )
    .bind(targetPublicId)
    .first<{ device_id: string }>();

  if (!target) {
    return c.json({ error: 'User not found' }, 404);
  }

  await c.env.DB.prepare(
    'INSERT OR IGNORE INTO blocks (blocker_device_id, blocked_device_id) VALUES (?, ?)',
  )
    .bind(blockerDeviceId, target.device_id)
    .run();

  return c.json({ ok: true });
});

/**
 * DELETE /block/:publicId — Unblock a user
 */
moderation.delete('/block/:publicId', requireAuth, async (c) => {
  const targetPublicId = c.req.param('publicId');
  const blockerDeviceId = c.get('deviceId');

  // Resolve publicId to device_id
  const target = await c.env.DB.prepare(
    'SELECT device_id FROM devices WHERE public_id = ?',
  )
    .bind(targetPublicId)
    .first<{ device_id: string }>();

  if (!target) {
    return c.json({ error: 'User not found' }, 404);
  }

  await c.env.DB.prepare(
    'DELETE FROM blocks WHERE blocker_device_id = ? AND blocked_device_id = ?',
  )
    .bind(blockerDeviceId, target.device_id)
    .run();

  return c.json({ ok: true });
});

// ---------------------------------------------------------------------------
// Admin routes
// ---------------------------------------------------------------------------

export const admin = new Hono<{ Bindings: Env }>();

/**
 * Admin auth middleware — checks X-Admin-Key header
 */
admin.use('*', async (c, next) => {
  const adminKey = c.req.header('X-Admin-Key');
  if (!adminKey || adminKey !== c.env.ADMIN_KEY) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  await next();
});

/**
 * GET /admin/reports — List reports
 * Query: ?status=pending (default)
 */
admin.get('/reports', async (c) => {
  const status = c.req.query('status') ?? 'pending';

  const { results } = await c.env.DB.prepare(
    `SELECT r.id, r.reporter_device_id, d.public_id AS reporter_public_id,
            r.target_type, r.target_id, r.reason, r.details, r.status, r.created_at
     FROM reports r
     LEFT JOIN devices d ON d.device_id = r.reporter_device_id
     WHERE r.status = ?
     ORDER BY r.created_at DESC`,
  )
    .bind(status)
    .all();

  return c.json({ reports: results ?? [] });
});

/**
 * POST /admin/action — Take moderation action
 * Body: { action, target_type, target_id }
 */
admin.post('/action', async (c) => {
  let body: {
    action?: string;
    target_type?: string;
    target_id?: string;
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { action, target_type, target_id } = body;

  const validActions = ['remove_content', 'block_user'];
  if (!action || !validActions.includes(action)) {
    return c.json({ error: 'action must be one of: remove_content, block_user' }, 400);
  }

  if (!target_type || !target_id) {
    return c.json({ error: 'target_type and target_id are required' }, 400);
  }

  if (action === 'remove_content') {
    if (target_type === 'pack') {
      await c.env.DB.prepare(
        'UPDATE packs SET is_removed = TRUE WHERE id = ?',
      )
        .bind(target_id)
        .run();
    } else if (target_type === 'submission') {
      await c.env.DB.prepare(
        'UPDATE submissions SET is_removed = TRUE WHERE id = ?',
      )
        .bind(target_id)
        .run();
    } else {
      return c.json({ error: 'remove_content only supports pack or submission target_type' }, 400);
    }
  } else if (action === 'block_user') {
    await c.env.DB.prepare(
      'UPDATE devices SET is_blocked = TRUE WHERE device_id = ?',
    )
      .bind(target_id)
      .run();
  }

  // Update matching reports to 'actioned'
  await c.env.DB.prepare(
    "UPDATE reports SET status = 'actioned' WHERE target_type = ? AND target_id = ? AND status = 'pending'",
  )
    .bind(target_type, target_id)
    .run();

  return c.json({ ok: true });
});

/**
 * POST /admin/challenges — Create a new challenge
 * Body: { title, description, theme, starts_at, voting_at, ends_at }
 */
admin.post('/challenges', async (c) => {
  let body: {
    title?: string;
    description?: string;
    theme?: string;
    starts_at?: string;
    voting_at?: string;
    ends_at?: string;
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { title, description, theme, starts_at, voting_at, ends_at } = body;

  if (!title || typeof title !== 'string' || title.trim().length === 0) {
    return c.json({ error: 'title is required' }, 400);
  }

  if (!starts_at || !voting_at || !ends_at) {
    return c.json({ error: 'starts_at, voting_at, and ends_at are required' }, 400);
  }

  const challengeId = crypto.randomUUID();

  await c.env.DB.prepare(
    `INSERT INTO challenges (id, title, description, theme, status, starts_at, voting_at, ends_at)
     VALUES (?, ?, ?, ?, 'upcoming', ?, ?, ?)`,
  )
    .bind(
      challengeId,
      title.trim(),
      description ?? null,
      theme ?? null,
      starts_at,
      voting_at,
      ends_at,
    )
    .run();

  return c.json({ id: challengeId }, 201);
});

export default moderation;
