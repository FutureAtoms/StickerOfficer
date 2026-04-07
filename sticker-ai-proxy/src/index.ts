import { Hono } from 'hono';
import { cors } from 'hono/cors';
import authRoutes from './routes/auth';
import packs from './routes/packs';
import challengeRoutes from './routes/challenges';
import feedRoutes from './routes/feed';
import generateRoutes from './routes/generate';
import removeBgRoutes from './routes/removeBg';
import moderation, { admin } from './routes/moderation';
import profile from './routes/profile';

export type Env = {
  DB: D1Database;
  R2: R2Bucket;
  KV: KVNamespace;
  JWT_SECRET: string;
  HF_API_KEY: string;
  ADMIN_KEY: string;
  GOOGLE_CLIENT_IDS: string;   // comma-separated list of allowed Google OAuth client IDs (Android, iOS, Web)
  APPLE_BUNDLE_ID: string;     // iOS bundle ID for Apple Sign-In audience validation
};

const app = new Hono<{ Bindings: Env }>();

app.use('*', cors());

app.get('/health', (c) => c.json({ status: 'ok' }));

// Legal pages
app.get('/legal/privacy', (c) => {
  return c.html(`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Privacy Policy - StickerOfficer</title><style>body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 20px;line-height:1.6;color:#333}h1{color:#FF6B6B}h2{color:#A855F7;margin-top:2em}</style></head><body>
<h1>Privacy Policy</h1>
<p><strong>Last updated:</strong> April 6, 2026</p>
<p>StickerOfficer ("the App") is developed by Future Atoms. This policy describes how we collect, use, and protect your information.</p>
<h2>Data We Collect</h2>
<ul>
<li><strong>Device ID</strong> — A randomly generated UUID stored on your device, used to identify your account. It is not linked to your real identity.</li>
<li><strong>Public ID</strong> — A short identifier (e.g., user_abc123) shown on your profile.</li>
<li><strong>Google/Apple Sign-In</strong> — If you choose to sign in, we receive your name, email, and profile photo from the provider. We do not receive or store your password.</li>
<li><strong>Sticker content</strong> — Stickers you publish to the community feed are stored on our servers.</li>
<li><strong>Usage data</strong> — Likes, downloads, and challenge votes are tracked to power the community features.</li>
</ul>
<h2>Data We Do NOT Collect</h2>
<ul>
<li>Location data</li>
<li>Contacts</li>
<li>Phone number</li>
<li>Payment information</li>
<li>Stickers you create but do not publish (these stay on your device)</li>
</ul>
<h2>How We Use Your Data</h2>
<p>Your data is used solely to operate the App: authenticate your device, display your profile, serve community content, and prevent abuse.</p>
<h2>Data Sharing</h2>
<p>We do not sell or share your personal data with third parties. Published stickers are visible to other users in the community feed.</p>
<h2>Data Storage & Security</h2>
<p>Data is stored on Cloudflare's global network (D1 database, R2 storage) and encrypted in transit via HTTPS.</p>
<h2>Data Deletion</h2>
<p>To request deletion of your data, email <a href="mailto:support@futureatoms.com">support@futureatoms.com</a> with your Public ID. We will delete your account and associated data within 30 days.</p>
<h2>Children's Privacy</h2>
<p>The App is not directed at children under 13. We do not knowingly collect data from children.</p>
<h2>Contact</h2>
<p>For questions about this policy, contact <a href="mailto:support@futureatoms.com">support@futureatoms.com</a>.</p>
</body></html>`);
});

app.get('/legal/terms', (c) => {
  return c.html(`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Terms of Service - StickerOfficer</title><style>body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 20px;line-height:1.6;color:#333}h1{color:#FF6B6B}h2{color:#A855F7;margin-top:2em}</style></head><body>
<h1>Terms of Service</h1>
<p><strong>Last updated:</strong> April 6, 2026</p>
<p>By using StickerOfficer ("the App"), you agree to these terms.</p>
<h2>Use of the App</h2>
<p>You may use the App to create, edit, share, and discover stickers. You must not use it to create or distribute content that is illegal, hateful, sexually explicit, or infringes on others' rights.</p>
<h2>User Content</h2>
<p>You retain ownership of stickers you create. By publishing to the community feed, you grant us a non-exclusive license to display and distribute your content within the App.</p>
<h2>Account</h2>
<p>Your device is automatically registered when you first open the App. You may optionally link a Google or Apple account. You are responsible for maintaining the security of your device.</p>
<h2>Moderation</h2>
<p>We may remove content or block accounts that violate these terms. You can report inappropriate content within the App.</p>
<h2>Disclaimer</h2>
<p>The App is provided "as is" without warranties. We are not liable for any damages arising from your use of the App.</p>
<h2>Changes</h2>
<p>We may update these terms. Continued use of the App constitutes acceptance of the updated terms.</p>
<h2>Contact</h2>
<p>Questions? Email <a href="mailto:support@futureatoms.com">support@futureatoms.com</a>.</p>
</body></html>`);
});

app.get('/legal/delete', (c) => {
  return c.html(`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Delete Account - StickerOfficer</title><style>body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 20px;line-height:1.6;color:#333}h1{color:#FF6B6B}</style></head><body>
<h1>Delete Your Account</h1>
<p>To request deletion of your StickerOfficer account and all associated data:</p>
<ol>
<li>Open the App and go to <strong>Profile</strong></li>
<li>Copy your Public ID (e.g., @user_abc123)</li>
<li>Send an email to <a href="mailto:support@futureatoms.com">support@futureatoms.com</a> with subject "Delete Account" and include your Public ID</li>
</ol>
<p>We will delete your account, published stickers, likes, and all associated data within 30 days.</p>
<p><strong>What gets deleted:</strong> Device record, published packs, sticker files, likes, downloads, challenge submissions, votes, reports, and blocks.</p>
<p><strong>What is NOT recoverable:</strong> Once deleted, your data cannot be restored.</p>
</body></html>`);
});

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

// Background removal: POST /remove-bg
app.route('/remove-bg', removeBgRoutes);

// Moderation routes: /report, /block/:publicId
app.route('/', moderation);

// Profile routes: /profile/:publicId
app.route('/profile', profile);

// Admin routes: /admin/reports, /admin/action, /admin/challenges
app.route('/admin', admin);

// Batch pack registration (for CLI pipeline)
app.post('/packs/register-batch', async (c) => {
  const adminKey = c.req.header('Authorization')?.replace('Bearer ', '');
  if (adminKey !== c.env.ADMIN_KEY) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { packs } = await c.req.json<{
    packs: Array<{
      id: string;
      name: string;
      author_device_id: string;
      sticker_count: number;
      is_public: boolean;
      tags: string;
      stickers: Array<{ r2_key: string; emojis: string[]; position: number }>;
    }>;
  }>();

  if (!packs || !Array.isArray(packs)) {
    return c.json({ error: 'packs array required' }, 400);
  }

  let registered = 0;
  for (const pack of packs) {
    await c.env.DB.prepare(
      'INSERT OR IGNORE INTO packs (id, name, author_device_id, sticker_count, is_public, tags) VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(pack.id, pack.name, pack.author_device_id, pack.sticker_count, pack.is_public, pack.tags)
      .run();

    for (const sticker of pack.stickers) {
      const stickerId = `${pack.id}_${sticker.position}`;
      await c.env.DB.prepare(
        'INSERT OR IGNORE INTO stickers (id, pack_id, r2_key, position) VALUES (?, ?, ?, ?)',
      )
        .bind(stickerId, pack.id, sticker.r2_key, sticker.position)
        .run();

      if (sticker.emojis && sticker.emojis.length > 0) {
        await c.env.DB.prepare(
          'INSERT OR IGNORE INTO sticker_metadata (id, pack_id, sticker_index, emojis, r2_key) VALUES (?, ?, ?, ?, ?)',
        )
          .bind(stickerId, pack.id, sticker.position, JSON.stringify(sticker.emojis), sticker.r2_key)
          .run();
      }
    }
    registered++;
  }

  return c.json({ ok: true, count: registered });
});

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
