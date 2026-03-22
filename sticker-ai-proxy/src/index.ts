import { Hono } from 'hono';
import { cors } from 'hono/cors';
import authRoutes from './routes/auth';
import packs from './routes/packs';
import challengeRoutes from './routes/challenges';
import feedRoutes from './routes/feed';
import generateRoutes from './routes/generate';
import moderation, { admin } from './routes/moderation';
import profile from './routes/profile';

export type Env = {
  DB: D1Database;
  R2: R2Bucket;
  KV: KVNamespace;
  JWT_SECRET: string;
  HF_API_KEY: string;
  ADMIN_KEY: string;
};

const app = new Hono<{ Bindings: Env }>();

app.use('*', cors());

app.get('/health', (c) => c.json({ status: 'ok' }));

// Auth routes: /auth/register, /auth/refresh, /auth/accept-terms
app.route('/auth', authRoutes);

// Pack routes: /packs (publish, like, download, list)
app.route('/packs', packs);

// Challenge routes: /challenges (list, submit, vote, submissions)
app.route('/challenges', challengeRoutes);

// Feed routes: /feed (trending, recent)
app.route('/feed', feedRoutes);

// AI generation routes: POST /generate
app.route('/generate', generateRoutes);

// Moderation routes: /report, /block/:publicId
app.route('/', moderation);

// Profile routes: /profile/:publicId
app.route('/profile', profile);

// Admin routes: /admin/reports, /admin/action, /admin/challenges
app.route('/admin', admin);

// R2 sticker serving: /r2/catalog.json, /r2/:packId/:sticker
app.get('/r2/catalog.json', async (c) => {
  const object = await c.env.R2.get('catalog.json');
  if (!object) return c.json({ error: 'catalog not found' }, 404);
  c.header('Content-Type', 'application/json');
  c.header('Cache-Control', 'public, max-age=300');
  return c.body(object.body as ReadableStream);
});

app.get('/r2/:packId/:sticker', async (c) => {
  const { packId, sticker } = c.req.param();
  const key = `packs/${packId}/${sticker}`;
  const object = await c.env.R2.get(key);
  if (!object) return c.json({ error: 'sticker not found' }, 404);

  const ext = sticker.split('.').pop()?.toLowerCase();
  const contentType =
    ext === 'webp' ? 'image/webp' :
    ext === 'png' ? 'image/png' :
    ext === 'gif' ? 'image/gif' :
    'application/octet-stream';

  c.header('Content-Type', contentType);
  c.header('Cache-Control', 'public, max-age=86400');
  return c.body(object.body as ReadableStream);
});

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env) {
    const now = new Date().toISOString();
    // upcoming -> active
    await env.DB.prepare(
      "UPDATE challenges SET status = 'active' WHERE status = 'upcoming' AND starts_at <= ?",
    )
      .bind(now)
      .run();
    // active -> voting
    await env.DB.prepare(
      "UPDATE challenges SET status = 'voting' WHERE status = 'active' AND voting_at <= ?",
    )
      .bind(now)
      .run();
    // voting -> completed
    await env.DB.prepare(
      "UPDATE challenges SET status = 'completed' WHERE status = 'voting' AND ends_at <= ?",
    )
      .bind(now)
      .run();
  },
};
