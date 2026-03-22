import { MiddlewareHandler } from 'hono';
import type { Env } from '../index';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type AuthEnv = { Bindings: Env; Variables: AuthVariables };

const MAX_REQUESTS = 5;
const WINDOW_SECONDS = 3600; // 1 hour

interface RateLimitEntry {
  count: number;
  resetAt: number; // epoch seconds
}

/**
 * rateLimit middleware:
 *  - KV-based rate limiting per device_id (from JWT / auth middleware)
 *  - Allows MAX_REQUESTS requests per WINDOW_SECONDS window
 *  - Returns 429 with retry_after when limit is exceeded
 */
export const rateLimit: MiddlewareHandler<AuthEnv> = async (c, next) => {
  const deviceId = c.get('deviceId');
  const kvKey = `ratelimit:generate:${deviceId}`;

  const now = Math.floor(Date.now() / 1000);

  // Read current rate-limit state from KV
  const existing = await c.env.KV.get<RateLimitEntry>(kvKey, 'json');

  if (existing && existing.resetAt > now) {
    // Window still active
    if (existing.count >= MAX_REQUESTS) {
      const retryAfter = existing.resetAt - now;
      return c.json(
        { error: 'Rate limit exceeded. Try again later.', retry_after: retryAfter },
        429,
      );
    }

    // Increment count, keep existing TTL
    const updated: RateLimitEntry = {
      count: existing.count + 1,
      resetAt: existing.resetAt,
    };
    const ttl = existing.resetAt - now;
    await c.env.KV.put(kvKey, JSON.stringify(updated), {
      expirationTtl: ttl > 0 ? ttl : 1,
    });
  } else {
    // Start a new window
    const entry: RateLimitEntry = {
      count: 1,
      resetAt: now + WINDOW_SECONDS,
    };
    await c.env.KV.put(kvKey, JSON.stringify(entry), {
      expirationTtl: WINDOW_SECONDS,
    });
  }

  await next();
};
