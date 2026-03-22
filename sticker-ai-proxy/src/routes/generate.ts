import { Hono } from 'hono';
import type { Env } from '../index';
import { requireAuth } from '../middleware/auth';
import { promptFilter } from '../middleware/promptFilter';
import { rateLimit } from '../middleware/rateLimit';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

const generate = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

const HF_MODEL_URL =
  'https://router.huggingface.co/hf-inference/models/stabilityai/stable-diffusion-xl-base-1.0';

const STICKER_PREFIX =
  'safe for children, family friendly, sticker style, die-cut sticker, white outline border, cartoon, kawaii, cute, simple background, high quality, ';

const MAX_COUNT = 4;
const DEFAULT_COUNT = 4;
const MIN_PROMPT_LENGTH = 1;
const MAX_PROMPT_LENGTH = 500;

/**
 * Convert an ArrayBuffer of binary image data to a base64 string.
 */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Call the Hugging Face Inference API to generate a single image.
 */
async function generateImage(
  stickerPrompt: string,
  seed: number,
  apiKey: string,
): Promise<string | null> {
  try {
    const response = await fetch(HF_MODEL_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        inputs: stickerPrompt,
        parameters: {
          seed,
          num_inference_steps: 20,
          guidance_scale: 7.5,
        },
      }),
    });

    if (!response.ok) {
      console.error(
        `HF API error: ${response.status} ${response.statusText}`,
      );
      return null;
    }

    const imageBuffer = await response.arrayBuffer();
    return arrayBufferToBase64(imageBuffer);
  } catch (err) {
    console.error('HF API fetch error:', err);
    return null;
  }
}

/**
 * POST /generate
 * Middleware chain: requireAuth -> promptFilter -> rateLimit
 * Body: { prompt: string, count?: number }
 * Returns: { images: string[] }
 */
generate.post('/', requireAuth, promptFilter, rateLimit, async (c) => {
  // Body was already parsed and validated by promptFilter.
  // Re-parse since Hono consumes the body stream once.
  let prompt: string;
  let count: number;

  try {
    // promptFilter already validated the body, but the stream is consumed.
    // We need to re-read — Hono caches the parsed JSON internally.
    const body = await c.req.json<{ prompt: string; count?: number }>();
    prompt = body.prompt;
    count = body.count ?? DEFAULT_COUNT;
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  // Validate prompt length
  if (
    typeof prompt !== 'string' ||
    prompt.length < MIN_PROMPT_LENGTH ||
    prompt.length > MAX_PROMPT_LENGTH
  ) {
    return c.json(
      { error: `Prompt must be between ${MIN_PROMPT_LENGTH} and ${MAX_PROMPT_LENGTH} characters` },
      400,
    );
  }

  // Validate and cap count
  if (typeof count !== 'number' || count < 1) {
    count = DEFAULT_COUNT;
  }
  if (count > MAX_COUNT) {
    count = MAX_COUNT;
  }

  const stickerPrompt = STICKER_PREFIX + prompt;
  const baseSeed = Date.now();

  // Generate images in parallel with different seeds
  const promises: Promise<string | null>[] = [];
  for (let i = 0; i < count; i++) {
    promises.push(generateImage(stickerPrompt, baseSeed + i, c.env.HF_API_KEY));
  }

  const results = await Promise.all(promises);

  // Filter out failed generations (nulls)
  const images = results.filter((img): img is string => img !== null);

  if (images.length === 0) {
    return c.json({ error: 'AI generation failed' }, 502);
  }

  return c.json({ images });
});

export default generate;
