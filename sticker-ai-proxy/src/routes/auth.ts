import { Hono } from 'hono';
import type { Env } from '../index';
import { signJwt } from '../utils/jwt';
import { generatePublicId } from '../utils/publicId';
import { requireAuth } from '../middleware/auth';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

const auth = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

const EXPIRES_IN = 31_536_000; // 1 year in seconds

/**
 * POST /register
 * Body: { device_id: string }
 * Creates device (or returns existing) and issues JWT.
 */
auth.post('/register', async (c) => {
  let body: { device_id?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const deviceId = body.device_id;
  if (!deviceId || typeof deviceId !== 'string' || deviceId.trim().length === 0) {
    return c.json({ error: 'device_id is required' }, 400);
  }

  // Check if device already exists
  const existing = await c.env.DB.prepare(
    'SELECT public_id FROM devices WHERE device_id = ?',
  )
    .bind(deviceId)
    .first<{ public_id: string }>();

  let publicId: string;

  if (existing) {
    publicId = existing.public_id;
    // Update last_seen
    await c.env.DB.prepare(
      "UPDATE devices SET last_seen = datetime('now') WHERE device_id = ?",
    )
      .bind(deviceId)
      .run();
  } else {
    publicId = generatePublicId();
    await c.env.DB.prepare(
      'INSERT INTO devices (device_id, public_id) VALUES (?, ?)',
    )
      .bind(deviceId, publicId)
      .run();
  }

  const token = await signJwt(
    { sub: deviceId, pid: publicId },
    c.env.JWT_SECRET,
    EXPIRES_IN,
  );

  return c.json({ token, public_id: publicId, expires_in: EXPIRES_IN });
});

/**
 * POST /refresh
 * Requires valid JWT. Re-signs with same claims.
 */
auth.post('/refresh', requireAuth, async (c) => {
  const deviceId = c.get('deviceId');
  const publicId = c.get('publicId');

  const token = await signJwt(
    { sub: deviceId, pid: publicId },
    c.env.JWT_SECRET,
    EXPIRES_IN,
  );

  return c.json({ token, public_id: publicId, expires_in: EXPIRES_IN });
});

/**
 * POST /accept-terms
 * Requires valid JWT. Sets terms_accepted_at = now.
 */
auth.post('/accept-terms', requireAuth, async (c) => {
  const deviceId = c.get('deviceId');

  await c.env.DB.prepare(
    "UPDATE devices SET terms_accepted_at = datetime('now') WHERE device_id = ?",
  )
    .bind(deviceId)
    .run();

  return c.json({ ok: true });
});

export default auth;
