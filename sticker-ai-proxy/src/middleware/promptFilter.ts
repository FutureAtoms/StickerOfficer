import { MiddlewareHandler } from 'hono';
import type { Env } from '../index';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type AuthEnv = { Bindings: Env; Variables: AuthVariables };

const BLOCKED_TERMS = [
  'nude', 'naked', 'nsfw', 'porn', 'sex', 'kill', 'murder', 'gore',
  'blood', 'weapon', 'gun', 'knife', 'drug', 'cocaine', 'heroin',
  'racist', 'nazi', 'terrorist', 'suicide', 'self-harm',
  'violence', 'hate', 'slur', 'torture', 'abuse', 'assault',
  'explicit', 'obscene', 'profanity', 'vulgar',
];

/**
 * Build a regex that matches any blocked term as a whole word,
 * case-insensitive. Terms with hyphens use escaped hyphens
 * instead of word-boundary anchors on the hyphen side.
 */
function buildBlockedRegex(): RegExp {
  const patterns = BLOCKED_TERMS.map((term) => {
    // Escape any regex-special characters in the term
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // Use word boundaries for whole-word matching
    return `\\b${escaped}\\b`;
  });
  return new RegExp(patterns.join('|'), 'i');
}

const blockedRegex = buildBlockedRegex();

/**
 * promptFilter middleware:
 *  - Reads the JSON body and checks the `prompt` field
 *  - Rejects prompts containing violence, NSFW, hate speech, or self-harm terms
 *  - Returns 400 with an error message if a blocked term is found
 */
export const promptFilter: MiddlewareHandler<AuthEnv> = async (c, next) => {
  let body: { prompt?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const prompt = body.prompt;
  if (typeof prompt !== 'string') {
    return c.json({ error: 'prompt is required' }, 400);
  }

  if (blockedRegex.test(prompt)) {
    return c.json({ error: 'Prompt contains prohibited content' }, 400);
  }

  // Store parsed body so downstream handlers don't need to re-parse
  c.set('parsedBody' as never, body as never);

  await next();
};
