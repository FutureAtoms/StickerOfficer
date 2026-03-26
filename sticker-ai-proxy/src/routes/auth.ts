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

/**
 * POST /google
 * Body: { id_token: string, device_id?: string }
 * Verifies Google ID token, creates/links account, issues JWT.
 */
auth.post('/google', async (c) => {
  let body: { id_token?: string; device_id?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const idToken = body.id_token;
  if (!idToken) {
    return c.json({ error: 'id_token is required' }, 400);
  }

  // Verify Google ID token
  const googleUser = await verifyGoogleToken(idToken);
  if (!googleUser) {
    return c.json({ error: 'Invalid Google ID token' }, 401);
  }

  // Check if Google account already linked
  const existingByGoogle = await c.env.DB.prepare(
    'SELECT device_id, public_id FROM devices WHERE google_id = ?',
  )
    .bind(googleUser.sub)
    .first<{ device_id: string; public_id: string }>();

  let deviceId: string;
  let publicId: string;

  if (existingByGoogle) {
    deviceId = existingByGoogle.device_id;
    publicId = existingByGoogle.public_id;
    await c.env.DB.prepare(
      "UPDATE devices SET last_seen = datetime('now'), google_name = ?, google_photo = ? WHERE device_id = ?",
    )
      .bind(googleUser.name, googleUser.picture, deviceId)
      .run();
  } else if (body.device_id) {
    const existingDevice = await c.env.DB.prepare(
      'SELECT public_id FROM devices WHERE device_id = ?',
    )
      .bind(body.device_id)
      .first<{ public_id: string }>();

    if (existingDevice) {
      deviceId = body.device_id;
      publicId = existingDevice.public_id;
      await c.env.DB.prepare(
        'UPDATE devices SET google_id = ?, google_email = ?, google_name = ?, google_photo = ? WHERE device_id = ?',
      )
        .bind(googleUser.sub, googleUser.email, googleUser.name, googleUser.picture, deviceId)
        .run();
    } else {
      deviceId = body.device_id;
      publicId = generatePublicId();
      await c.env.DB.prepare(
        'INSERT INTO devices (device_id, public_id, google_id, google_email, google_name, google_photo) VALUES (?, ?, ?, ?, ?, ?)',
      )
        .bind(deviceId, publicId, googleUser.sub, googleUser.email, googleUser.name, googleUser.picture)
        .run();
    }
  } else {
    deviceId = `google_${googleUser.sub}`;
    publicId = generatePublicId();
    await c.env.DB.prepare(
      'INSERT INTO devices (device_id, public_id, google_id, google_email, google_name, google_photo) VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(deviceId, publicId, googleUser.sub, googleUser.email, googleUser.name, googleUser.picture)
      .run();
  }

  const token = await signJwt(
    { sub: deviceId, pid: publicId },
    c.env.JWT_SECRET,
    EXPIRES_IN,
  );

  return c.json({
    token,
    public_id: publicId,
    google_name: googleUser.name,
    google_photo: googleUser.picture,
    expires_in: EXPIRES_IN,
  });
});


async function verifyGoogleToken(idToken: string): Promise<{
  sub: string; email: string; name: string; picture: string;
} | null> {
  try {
    const resp = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`,
    );
    if (!resp.ok) return null;
    const data = await resp.json() as Record<string, string>;
    return {
      sub: data.sub,
      email: data.email || '',
      name: data.name || '',
      picture: data.picture || '',
    };
  } catch {
    return null;
  }
}

export default auth;
