import { Hono } from 'hono';
import { cors } from 'hono/cors';
import authRoutes from './routes/auth';
import packs from './routes/packs';
import challengeRoutes from './routes/challenges';
import feedRoutes from './routes/feed';
import generateRoutes from './routes/generate';

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

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Env) {
    // Challenge lifecycle cron — implemented later
  },
};
