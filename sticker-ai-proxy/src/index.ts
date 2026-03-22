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
