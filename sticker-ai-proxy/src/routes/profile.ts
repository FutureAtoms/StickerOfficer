import { Hono } from 'hono';
import type { Env } from '../index';

const profile = new Hono<{ Bindings: Env }>();

/**
 * GET /profile/:publicId — Public profile
 * Returns profile info without exposing device_id.
 */
profile.get('/:publicId', async (c) => {
  const publicId = c.req.param('publicId');

  const device = await c.env.DB.prepare(
    `SELECT d.public_id, d.display_name, d.packs_created, d.created_at AS first_seen,
            COALESCE(SUM(p.like_count), 0) AS total_likes_received
     FROM devices d
     LEFT JOIN packs p ON p.author_device_id = d.device_id AND p.is_removed = FALSE
     WHERE d.public_id = ?
     GROUP BY d.device_id`,
  )
    .bind(publicId)
    .first<{
      public_id: string;
      display_name: string | null;
      packs_created: number;
      first_seen: string;
      total_likes_received: number;
    }>();

  if (!device) {
    return c.json({ error: 'User not found' }, 404);
  }

  return c.json({
    public_id: device.public_id,
    display_name: device.display_name,
    packs_created: device.packs_created,
    total_likes_received: device.total_likes_received,
    first_seen: device.first_seen,
  });
});

export default profile;
