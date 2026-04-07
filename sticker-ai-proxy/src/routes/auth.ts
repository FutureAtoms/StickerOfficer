import { Hono } from 'hono';
import type { Env } from '../index';
import { signJwt, fromBase64Url } from '../utils/jwt';
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

  return c.json({ token, public_id: publicId, device_id: deviceId, expires_in: EXPIRES_IN });
});

/**
 * POST /refresh
 * Body: { device_id: string }
 * Validates device exists and re-issues JWT. No auth required —
 * the device_id itself is a UUID secret, and requiring a valid token
 * to refresh creates a chicken-and-egg problem when the token expires.
 */
auth.post('/refresh', async (c) => {
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

  const device = await c.env.DB.prepare(
    'SELECT public_id, is_blocked FROM devices WHERE device_id = ?',
  )
    .bind(deviceId)
    .first<{ public_id: string; is_blocked: number | boolean }>();

  if (!device) {
    return c.json({ error: 'Device not found' }, 404);
  }

  if (device.is_blocked) {
    return c.json({ error: 'Device is blocked' }, 403);
  }

  // Update last_seen
  await c.env.DB.prepare(
    "UPDATE devices SET last_seen = datetime('now') WHERE device_id = ?",
  )
    .bind(deviceId)
    .run();

  const token = await signJwt(
    { sub: deviceId, pid: device.public_id },
    c.env.JWT_SECRET,
    EXPIRES_IN,
  );

  return c.json({ token, public_id: device.public_id, device_id: deviceId, expires_in: EXPIRES_IN });
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

  // Verify Google ID token (with audience validation)
  const allowedGoogleClientIds = c.env.GOOGLE_CLIENT_IDS
    ? c.env.GOOGLE_CLIENT_IDS.split(',').map((id) => id.trim()).filter((id) => id.length > 0)
    : [];
  if (allowedGoogleClientIds.length === 0) {
    return c.json({ error: 'Google Sign-In not configured (GOOGLE_CLIENT_IDS missing)' }, 503);
  }
  const googleUser = await verifyGoogleToken(idToken, allowedGoogleClientIds);
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
    device_id: deviceId,
    auth_method: 'google',
    google_name: googleUser.name,
    google_email: googleUser.email,
    google_photo: googleUser.picture,
    expires_in: EXPIRES_IN,
  });
});


/**
 * POST /apple
 * Body: { identity_token: string, device_id?: string, full_name?: string }
 * Verifies Apple identity token, creates/links account, issues JWT.
 * full_name is accepted because Apple only provides the name on the first authorization.
 */
auth.post('/apple', async (c) => {
  let body: { identity_token?: string; device_id?: string; full_name?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const identityToken = body.identity_token;
  if (!identityToken) {
    return c.json({ error: 'identity_token is required' }, 400);
  }

  // Verify Apple identity token
  if (!c.env.APPLE_BUNDLE_ID) {
    return c.json({ error: 'Apple Sign-In not configured (APPLE_BUNDLE_ID missing)' }, 503);
  }
  const appleUser = await verifyAppleToken(identityToken, c.env.APPLE_BUNDLE_ID, c.env.KV);
  if (!appleUser) {
    return c.json({ error: 'Invalid Apple identity token' }, 401);
  }

  // Use client-provided name (Apple only sends it on first auth)
  const appleName = body.full_name || appleUser.name || '';

  // Check if Apple account already linked
  const existingByApple = await c.env.DB.prepare(
    'SELECT device_id, public_id FROM devices WHERE apple_id = ?',
  )
    .bind(appleUser.sub)
    .first<{ device_id: string; public_id: string }>();

  let deviceId: string;
  let publicId: string;

  if (existingByApple) {
    // Existing Apple-linked account — return its identity
    deviceId = existingByApple.device_id;
    publicId = existingByApple.public_id;
    await c.env.DB.prepare(
      "UPDATE devices SET last_seen = datetime('now'), apple_name = ? WHERE device_id = ?",
    )
      .bind(appleName, deviceId)
      .run();
  } else if (body.device_id) {
    // Link Apple to existing anonymous device
    const existingDevice = await c.env.DB.prepare(
      'SELECT public_id FROM devices WHERE device_id = ?',
    )
      .bind(body.device_id)
      .first<{ public_id: string }>();

    if (existingDevice) {
      deviceId = body.device_id;
      publicId = existingDevice.public_id;
      await c.env.DB.prepare(
        'UPDATE devices SET apple_id = ?, apple_email = ?, apple_name = ? WHERE device_id = ?',
      )
        .bind(appleUser.sub, appleUser.email, appleName, deviceId)
        .run();
    } else {
      // device_id not found — create new device with Apple linked
      deviceId = body.device_id;
      publicId = generatePublicId();
      await c.env.DB.prepare(
        'INSERT INTO devices (device_id, public_id, apple_id, apple_email, apple_name) VALUES (?, ?, ?, ?, ?)',
      )
        .bind(deviceId, publicId, appleUser.sub, appleUser.email, appleName)
        .run();
    }
  } else {
    // No device_id — create brand new device
    deviceId = `apple_${appleUser.sub}`;
    publicId = generatePublicId();
    await c.env.DB.prepare(
      'INSERT INTO devices (device_id, public_id, apple_id, apple_email, apple_name) VALUES (?, ?, ?, ?, ?)',
    )
      .bind(deviceId, publicId, appleUser.sub, appleUser.email, appleName)
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
    device_id: deviceId,
    auth_method: 'apple',
    apple_name: appleName,
    apple_email: appleUser.email,
    expires_in: EXPIRES_IN,
  });
});


// ---------------------------------------------------------------------------
// Token verification helpers
// ---------------------------------------------------------------------------

/**
 * Verify Apple identity token using JWKS.
 * Fetches Apple's public keys (cached in KV for 24h), validates RS256 signature,
 * issuer, audience, and expiry.
 */
async function verifyAppleToken(
  identityToken: string,
  expectedBundleId: string,
  kv: KVNamespace,
): Promise<{ sub: string; email: string; name: string } | null> {
  try {
    const parts = identityToken.split('.');
    if (parts.length !== 3) return null;

    const headerJson = new TextDecoder().decode(fromBase64Url(parts[0]));
    const header = JSON.parse(headerJson) as { kid: string; alg: string };
    if (header.alg !== 'RS256') return null;

    // Fetch Apple's JWKS (cached in KV)
    const jwks = await getAppleJWKS(kv);
    if (!jwks) return null;

    const matchingKey = jwks.keys.find(
      (k) => (k as { kid: string }).kid === header.kid,
    );
    if (!matchingKey) return null;

    // Import the RSA public key
    const publicKey = await crypto.subtle.importKey(
      'jwk',
      matchingKey,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );

    // Verify signature
    const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = fromBase64Url(parts[2]);
    const valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      publicKey,
      signature.buffer as ArrayBuffer,
      signingInput,
    );
    if (!valid) return null;

    // Decode and validate payload
    const payloadJson = new TextDecoder().decode(fromBase64Url(parts[1]));
    const payload = JSON.parse(payloadJson) as Record<string, unknown>;

    if (payload.iss !== 'https://appleid.apple.com') return null;
    if (expectedBundleId && payload.aud !== expectedBundleId) return null;
    if (typeof payload.exp === 'number' && payload.exp < Math.floor(Date.now() / 1000)) return null;

    return {
      sub: payload.sub as string,
      email: (payload.email as string) || '',
      name: '',  // Apple doesn't include name in the token — must be passed by client
    };
  } catch {
    return null;
  }
}

/** Fetch Apple JWKS with 24-hour KV cache */
async function getAppleJWKS(kv: KVNamespace): Promise<{ keys: Array<Record<string, unknown>> } | null> {
  const cacheKey = 'apple_jwks';
  const cached = await kv.get(cacheKey);
  if (cached) {
    return JSON.parse(cached);
  }

  try {
    const resp = await fetch('https://appleid.apple.com/auth/keys');
    if (!resp.ok) return null;
    const jwks = await resp.json() as { keys: Array<Record<string, unknown>> };
    // Cache for 24 hours
    await kv.put(cacheKey, JSON.stringify(jwks), { expirationTtl: 86400 });
    return jwks;
  } catch {
    return null;
  }
}

async function verifyGoogleToken(
  idToken: string,
  allowedClientIds: string[],
): Promise<{
  sub: string; email: string; name: string; picture: string;
} | null> {
  try {
    const resp = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`,
    );
    if (!resp.ok) return null;
    const data = await resp.json() as Record<string, string>;

    // Validate audience — reject tokens not issued for our app
    if (allowedClientIds.length > 0 && !allowedClientIds.includes(data.aud)) {
      return null;
    }

    // Validate issuer
    if (data.iss !== 'accounts.google.com' && data.iss !== 'https://accounts.google.com') {
      return null;
    }

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
