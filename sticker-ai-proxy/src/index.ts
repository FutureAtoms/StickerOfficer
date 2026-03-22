import { Hono } from 'hono';
import { cors } from 'hono/cors';

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

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Env) {
    // Challenge lifecycle cron — implemented later
  },
};
