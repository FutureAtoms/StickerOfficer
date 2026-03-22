import { Hono } from 'hono';
import type { Env } from '../index';
import { verifyJwt } from '../utils/jwt';

type FeedVariables = {
  deviceId: string | null;
};

const feed = new Hono<{ Bindings: Env; Variables: FeedVariables }>();

/**
 * Optionally extract the authenticated device_id from the Authorization header.
 * Does NOT reject unauthenticated requests — simply sets deviceId to null.
 */
const optionalAuth = async (
  c: { req: { header(name: string): string | undefined }; env: Env; set(key: 'deviceId', value: string | null): void },
  next: () => Promise<void>,
) => {
  const authHeader = c.req.header('Authorization');
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    try {
      const payload = await verifyJwt(token, c.env.JWT_SECRET);
      c.set('deviceId', payload.sub);
    } catch {
      // Invalid token — treat as unauthenticated
      c.set('deviceId', null);
    }
  } else {
    c.set('deviceId', null);
  }
  await next();
};

// Apply optional auth to all feed routes
feed.use('*', optionalAuth);

/**
 * GET /feed — Trending packs
 * Ranked by (like_count * 2 + download_count * 3) descending.
 */
feed.get('/', async (c) => {
  const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '20', 10) || 20, 1), 100);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);
  const deviceId = c.get('deviceId');

  let packsQuery: string;
  const bindValues: (string | number)[] = [];

  if (deviceId) {
    packsQuery = `
      SELECT p.*, d.public_id AS author_public_id
      FROM packs p
      JOIN devices d ON p.author_device_id = d.device_id
      WHERE p.is_public = 1
        AND p.is_removed = 0
        AND p.author_device_id NOT IN (
          SELECT blocked_device_id FROM blocks WHERE blocker_device_id = ?
        )
      ORDER BY (p.like_count * 2 + p.download_count * 3) DESC
      LIMIT ? OFFSET ?
    `;
    bindValues.push(deviceId, limit, offset);
  } else {
    packsQuery = `
      SELECT p.*, d.public_id AS author_public_id
      FROM packs p
      JOIN devices d ON p.author_device_id = d.device_id
      WHERE p.is_public = 1
        AND p.is_removed = 0
      ORDER BY (p.like_count * 2 + p.download_count * 3) DESC
      LIMIT ? OFFSET ?
    `;
    bindValues.push(limit, offset);
  }

  let countQuery: string;
  const countBindValues: string[] = [];

  if (deviceId) {
    countQuery = `
      SELECT COUNT(*) AS total
      FROM packs p
      WHERE p.is_public = 1
        AND p.is_removed = 0
        AND p.author_device_id NOT IN (
          SELECT blocked_device_id FROM blocks WHERE blocker_device_id = ?
        )
    `;
    countBindValues.push(deviceId);
  } else {
    countQuery = `
      SELECT COUNT(*) AS total
      FROM packs p
      WHERE p.is_public = 1
        AND p.is_removed = 0
    `;
  }

  const [packsResult, countResult] = await Promise.all([
    c.env.DB.prepare(packsQuery).bind(...bindValues).all(),
    c.env.DB.prepare(countQuery).bind(...countBindValues).all(),
  ]);

  const total = (countResult.results[0] as { total: number })?.total ?? 0;

  return c.json({ packs: packsResult.results, total });
});

/**
 * GET /feed/recent — Recently published packs
 * Ordered by created_at descending.
 */
feed.get('/recent', async (c) => {
  const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '20', 10) || 20, 1), 100);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);
  const deviceId = c.get('deviceId');

  let packsQuery: string;
  const bindValues: (string | number)[] = [];

  if (deviceId) {
    packsQuery = `
      SELECT p.*, d.public_id AS author_public_id
      FROM packs p
      JOIN devices d ON p.author_device_id = d.device_id
      WHERE p.is_public = 1
        AND p.is_removed = 0
        AND p.author_device_id NOT IN (
          SELECT blocked_device_id FROM blocks WHERE blocker_device_id = ?
        )
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `;
    bindValues.push(deviceId, limit, offset);
  } else {
    packsQuery = `
      SELECT p.*, d.public_id AS author_public_id
      FROM packs p
      JOIN devices d ON p.author_device_id = d.device_id
      WHERE p.is_public = 1
        AND p.is_removed = 0
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `;
    bindValues.push(limit, offset);
  }

  let countQuery: string;
  const countBindValues: string[] = [];

  if (deviceId) {
    countQuery = `
      SELECT COUNT(*) AS total
      FROM packs p
      WHERE p.is_public = 1
        AND p.is_removed = 0
        AND p.author_device_id NOT IN (
          SELECT blocked_device_id FROM blocks WHERE blocker_device_id = ?
        )
    `;
    countBindValues.push(deviceId);
  } else {
    countQuery = `
      SELECT COUNT(*) AS total
      FROM packs p
      WHERE p.is_public = 1
        AND p.is_removed = 0
    `;
  }

  const [packsResult, countResult] = await Promise.all([
    c.env.DB.prepare(packsQuery).bind(...bindValues).all(),
    c.env.DB.prepare(countQuery).bind(...countBindValues).all(),
  ]);

  const total = (countResult.results[0] as { total: number })?.total ?? 0;

  return c.json({ packs: packsResult.results, total });
});

export default feed;
