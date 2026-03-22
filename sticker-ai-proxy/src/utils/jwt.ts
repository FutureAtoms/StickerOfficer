/**
 * JWT sign / verify using Web Crypto API (HMAC-SHA256).
 * All encoding uses base64url (RFC 4648 section 5).
 */

// ---------------------------------------------------------------------------
// Base64url helpers
// ---------------------------------------------------------------------------

export function toBase64Url(data: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < data.byteLength; i++) {
    binary += String.fromCharCode(data[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromBase64Url(str: string): Uint8Array {
  // Restore standard base64
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  // Pad with '='
  while (base64.length % 4 !== 0) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

function encodeJsonBase64Url(obj: Record<string, unknown>): string {
  return toBase64Url(encoder.encode(JSON.stringify(obj)));
}

async function importKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface JwtPayload {
  sub: string;          // device_id
  pid: string;          // public_id
  iat: number;
  exp: number;
  [key: string]: unknown;
}

/**
 * Sign a JWT with HMAC-SHA256.
 * @param payload  Claims to include (sub, pid, etc.)
 * @param secret   HMAC secret string
 * @param expiresInSeconds  Token lifetime (default 1 year)
 */
export async function signJwt(
  payload: Omit<JwtPayload, 'iat' | 'exp'>,
  secret: string,
  expiresInSeconds = 31_536_000,
): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const fullPayload = {
    ...payload,
    iat: now,
    exp: now + expiresInSeconds,
  } as JwtPayload;

  const headerB64 = encodeJsonBase64Url(header);
  const payloadB64 = encodeJsonBase64Url(fullPayload as unknown as Record<string, unknown>);
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await importKey(secret);
  const signature = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput)),
  );

  return `${signingInput}.${toBase64Url(signature)}`;
}

/**
 * Verify a JWT. Returns the decoded payload or throws.
 */
export async function verifyJwt(token: string, secret: string): Promise<JwtPayload> {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWT format');
  }

  const [headerB64, payloadB64, signatureB64] = parts;
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = fromBase64Url(signatureB64);

  const key = await importKey(secret);
  const valid = await crypto.subtle.verify(
    'HMAC',
    key,
    signature.buffer as ArrayBuffer,
    encoder.encode(signingInput),
  );

  if (!valid) {
    throw new Error('Invalid JWT signature');
  }

  const payloadJson = new TextDecoder().decode(fromBase64Url(payloadB64));
  const payload: JwtPayload = JSON.parse(payloadJson);

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new Error('JWT expired');
  }

  return payload;
}
