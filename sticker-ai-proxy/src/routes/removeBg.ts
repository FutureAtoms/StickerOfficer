import { Hono } from 'hono';
import type { Env } from '../index';
import { requireAuth } from '../middleware/auth';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

const removeBg = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

const RMBG_MODEL_URL =
  'https://router.huggingface.co/hf-inference/models/briaai/RMBG-2.0';

// Rate limit: 20 requests per hour per device (more generous than generation)
const MAX_REQUESTS_PER_HOUR = 20;
const WINDOW_SECONDS = 3600;

/**
 * Simple per-device rate limiting via KV.
 */
async function checkRateLimit(
  kv: KVNamespace,
  deviceId: string,
): Promise<boolean> {
  const key = `ratelimit:removebg:${deviceId}`;
  const current = parseInt((await kv.get(key)) || '0', 10);
  if (current >= MAX_REQUESTS_PER_HOUR) {
    return false;
  }
  await kv.put(key, String(current + 1), { expirationTtl: WINDOW_SECONDS });
  return true;
}

/**
 * POST /remove-bg
 * Requires auth. Accepts base64 PNG, returns base64 PNG with transparent background.
 * Body: { image: string (base64 encoded PNG) }
 * Returns: { image: string (base64 encoded PNG with bg removed) }
 */
removeBg.post('/', requireAuth, async (c) => {
  const deviceId = c.get('deviceId');

  // Rate limit
  const allowed = await checkRateLimit(c.env.KV, deviceId);
  if (!allowed) {
    return c.json(
      { error: 'Rate limit exceeded. Try again later.' },
      429,
    );
  }

  // Parse body
  let body: { image?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const base64Image = body.image;
  if (!base64Image || typeof base64Image !== 'string') {
    return c.json({ error: 'image (base64 string) is required' }, 400);
  }

  // Decode base64 to binary
  let imageBuffer: ArrayBuffer;
  try {
    const binary = atob(base64Image);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    imageBuffer = bytes.buffer as ArrayBuffer;
  } catch {
    return c.json({ error: 'Invalid base64 image data' }, 400);
  }

  // Check image size (max 10MB)
  if (imageBuffer.byteLength > 10 * 1024 * 1024) {
    return c.json({ error: 'Image too large (max 10MB)' }, 400);
  }

  // Call HuggingFace RMBG-2.0 model
  try {
    const response = await fetch(RMBG_MODEL_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${c.env.HF_API_KEY}`,
        'Content-Type': 'image/png',
      },
      body: imageBuffer,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'Unknown error');
      console.error(`RMBG API error: ${response.status} ${errorText}`);

      if (response.status === 503) {
        return c.json(
          { error: 'AI model is loading, please try again in a few seconds' },
          503,
        );
      }
      return c.json({ error: 'Background removal failed' }, 502);
    }

    // Convert response to base64
    const resultBuffer = await response.arrayBuffer();
    const resultBytes = new Uint8Array(resultBuffer);
    let resultBinary = '';
    for (let i = 0; i < resultBytes.byteLength; i++) {
      resultBinary += String.fromCharCode(resultBytes[i]);
    }
    const resultBase64 = btoa(resultBinary);

    return c.json({ image: resultBase64 });
  } catch (err) {
    console.error('RMBG fetch error:', err);
    return c.json({ error: 'Background removal service unavailable' }, 502);
  }
});

export default removeBg;
