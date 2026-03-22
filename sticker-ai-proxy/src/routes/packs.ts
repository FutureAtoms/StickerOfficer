import { Hono } from 'hono';
import type { Env } from '../index';
import { requireAuth, requireTerms } from '../middleware/auth';

type AuthVariables = {
  deviceId: string;
  publicId: string;
};

type PackEnv = { Bindings: Env; Variables: AuthVariables };

export const packs = new Hono<PackEnv>();

/**
 * POST /packs — Publish a new sticker pack
 * Body: { name, category, tags: string[], stickers: { r2_key: string }[] }
 */
packs.post('/', requireAuth, requireTerms, async (c) => {
  let body: {
    name?: string;
    category?: string;
    tags?: string[];
    stickers?: { r2_key: string }[];
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { name, category, tags, stickers } = body;

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return c.json({ error: 'name is required' }, 400);
  }

  if (!stickers || !Array.isArray(stickers) || stickers.length === 0) {
    return c.json({ error: 'stickers array is required and must not be empty' }, 400);
  }

  for (const s of stickers) {
    if (!s.r2_key || typeof s.r2_key !== 'string') {
      return c.json({ error: 'Each sticker must have a valid r2_key' }, 400);
    }
  }

  const deviceId = c.get('deviceId');
  const packId = crypto.randomUUID();
  const tagsJson = tags ? JSON.stringify(tags) : null;

  // Insert pack
  await c.env.DB.prepare(
    `INSERT INTO packs (id, name, author_device_id, category, sticker_count, is_public, tags)
     VALUES (?, ?, ?, ?, ?, TRUE, ?)`,
  )
    .bind(packId, name.trim(), deviceId, category ?? null, stickers.length, tagsJson)
    .run();

  // Insert stickers
  for (let i = 0; i < stickers.length; i++) {
    const stickerId = crypto.randomUUID();
    await c.env.DB.prepare(
      'INSERT INTO stickers (id, pack_id, r2_key, position) VALUES (?, ?, ?, ?)',
    )
      .bind(stickerId, packId, stickers[i].r2_key, i)
      .run();
  }

  // Update packs_created
  await c.env.DB.prepare(
    'UPDATE devices SET packs_created = packs_created + 1 WHERE device_id = ?',
  )
    .bind(deviceId)
    .run();

  return c.json(
    {
      id: packId,
      name: name.trim(),
      category: category ?? null,
      tags: tags ?? [],
      sticker_count: stickers.length,
      like_count: 0,
      download_count: 0,
      is_public: true,
    },
    201,
  );
});

/**
 * POST /packs/:id/like — Like/unlike toggle
 */
packs.post('/:id/like', requireAuth, async (c) => {
  const packId = c.req.param('id');
  const deviceId = c.get('deviceId');

  // Check pack exists and is not removed
  const pack = await c.env.DB.prepare(
    'SELECT id, like_count FROM packs WHERE id = ? AND is_removed = FALSE',
  )
    .bind(packId)
    .first<{ id: string; like_count: number }>();

  if (!pack) {
    return c.json({ error: 'Pack not found' }, 404);
  }

  // Check if like already exists
  const existing = await c.env.DB.prepare(
    'SELECT device_id FROM likes WHERE device_id = ? AND pack_id = ?',
  )
    .bind(deviceId, packId)
    .first<{ device_id: string }>();

  let liked: boolean;
  let likeCount: number;

  if (existing) {
    // Unlike: remove the like and decrement
    await c.env.DB.prepare(
      'DELETE FROM likes WHERE device_id = ? AND pack_id = ?',
    )
      .bind(deviceId, packId)
      .run();

    await c.env.DB.prepare(
      'UPDATE packs SET like_count = like_count - 1 WHERE id = ?',
    )
      .bind(packId)
      .run();

    liked = false;
    likeCount = pack.like_count - 1;
  } else {
    // Like: insert and increment
    await c.env.DB.prepare(
      'INSERT INTO likes (device_id, pack_id) VALUES (?, ?)',
    )
      .bind(deviceId, packId)
      .run();

    await c.env.DB.prepare(
      'UPDATE packs SET like_count = like_count + 1 WHERE id = ?',
    )
      .bind(packId)
      .run();

    liked = true;
    likeCount = pack.like_count + 1;
  }

  return c.json({ liked, like_count: likeCount });
});

/**
 * POST /packs/:id/download — Track download (idempotent)
 */
packs.post('/:id/download', requireAuth, async (c) => {
  const packId = c.req.param('id');
  const deviceId = c.get('deviceId');

  // Check pack exists and is not removed
  const pack = await c.env.DB.prepare(
    'SELECT id, download_count FROM packs WHERE id = ? AND is_removed = FALSE',
  )
    .bind(packId)
    .first<{ id: string; download_count: number }>();

  if (!pack) {
    return c.json({ error: 'Pack not found' }, 404);
  }

  // INSERT OR IGNORE — idempotent
  const result = await c.env.DB.prepare(
    'INSERT OR IGNORE INTO downloads (device_id, pack_id) VALUES (?, ?)',
  )
    .bind(deviceId, packId)
    .run();

  let downloadCount = pack.download_count;

  // If a row was inserted (new download), increment count
  if (result.meta.changes > 0) {
    await c.env.DB.prepare(
      'UPDATE packs SET download_count = download_count + 1 WHERE id = ?',
    )
      .bind(packId)
      .run();
    downloadCount += 1;
  }

  return c.json({ downloaded: true, download_count: downloadCount });
});

/**
 * GET /packs — List packs by author
 * Query: ?author=<publicId>&limit=20&offset=0
 */
packs.get('/', async (c) => {
  const authorPublicId = c.req.query('author');

  if (!authorPublicId) {
    return c.json({ error: 'author query parameter is required' }, 400);
  }

  const limit = Math.min(parseInt(c.req.query('limit') ?? '20', 10) || 20, 100);
  const offset = parseInt(c.req.query('offset') ?? '0', 10) || 0;

  // Resolve public_id to device_id
  const device = await c.env.DB.prepare(
    'SELECT device_id FROM devices WHERE public_id = ?',
  )
    .bind(authorPublicId)
    .first<{ device_id: string }>();

  if (!device) {
    return c.json({ packs: [], total: 0 });
  }

  // Count total
  const countResult = await c.env.DB.prepare(
    'SELECT COUNT(*) as total FROM packs WHERE author_device_id = ? AND is_removed = FALSE',
  )
    .bind(device.device_id)
    .first<{ total: number }>();

  const total = countResult?.total ?? 0;

  // Fetch packs
  const { results } = await c.env.DB.prepare(
    `SELECT id, name, category, sticker_count, like_count, download_count, is_public, tags, created_at
     FROM packs
     WHERE author_device_id = ? AND is_removed = FALSE
     ORDER BY created_at DESC, rowid DESC
     LIMIT ? OFFSET ?`,
  )
    .bind(device.device_id, limit, offset)
    .all();

  const packsList = (results ?? []).map((row) => ({
    ...row,
    tags: row.tags ? JSON.parse(row.tags as string) : [],
  }));

  return c.json({ packs: packsList, total });
});

export default packs;
