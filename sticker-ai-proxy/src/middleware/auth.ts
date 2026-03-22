import { Context, MiddlewareHandler } from 'hono';
import type { Env } from '../index';
import { verifyJwt } from '../utils/jwt';

// Extend Hono's context variables for auth state
type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type AuthEnv = { Bindings: Env; Variables: AuthVariables };

/**
 * requireAuth middleware:
 *  - Extracts Bearer token from Authorization header
 *  - Verifies JWT signature and expiry
 *  - Checks the device is not blocked in D1
 *  - Sets deviceId and publicId on the context
 */
export const requireAuth: MiddlewareHandler<AuthEnv> = async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ error: 'Missing or invalid Authorization header' }, 401);
  }

  const token = authHeader.slice(7);
  let payload;
  try {
    payload = await verifyJwt(token, c.env.JWT_SECRET);
  } catch {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }

  // Check if device is blocked
  const device = await c.env.DB.prepare(
    'SELECT is_blocked FROM devices WHERE device_id = ?',
  )
    .bind(payload.sub)
    .first<{ is_blocked: number | boolean }>();

  if (!device) {
    return c.json({ error: 'Device not found' }, 401);
  }

  if (device.is_blocked) {
    return c.json({ error: 'Device is blocked' }, 403);
  }

  // Update last_seen
  await c.env.DB.prepare(
    "UPDATE devices SET last_seen = datetime('now') WHERE device_id = ?",
  )
    .bind(payload.sub)
    .run();

  c.set('deviceId', payload.sub);
  c.set('publicId', payload.pid);

  await next();
};

/**
 * requireTerms middleware:
 *  - Must be used AFTER requireAuth
 *  - Checks that terms_accepted_at is set for the device
 */
export const requireTerms: MiddlewareHandler<AuthEnv> = async (c, next) => {
  const deviceId = c.get('deviceId');

  const device = await c.env.DB.prepare(
    'SELECT terms_accepted_at FROM devices WHERE device_id = ?',
  )
    .bind(deviceId)
    .first<{ terms_accepted_at: string | null }>();

  if (!device || !device.terms_accepted_at) {
    return c.json({ error: 'Terms not accepted' }, 403);
  }

  await next();
};
