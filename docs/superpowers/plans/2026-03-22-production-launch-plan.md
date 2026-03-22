# StickerOfficer Production Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship StickerOfficer v1.0.0 to Play Store and App Store with a full Cloudflare backend, 810+ stickers, real social features, and automated store submission.

**Architecture:** Cloudflare Worker (TypeScript) serves as the full backend — JWT auth, D1 for social data, R2 for sticker storage, KV for rate limiting. Flutter app connects via `api_client.dart`. Maestro + Fastlane automate screenshots and store submission. No Firebase in v1.

**Tech Stack:** Flutter 3.29+, Dart 3.7+, Riverpod, GoRouter, Cloudflare Workers (TypeScript), D1 (SQLite), R2 (object storage), KV (rate limiting), Fastlane, Maestro, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-03-22-production-launch-design.md` (rev 5)

**Implementation notes from review:**
- Use `flutter_secure_storage` (not SharedPreferences) for JWT token
- Worker cron trigger in `wrangler.toml` for challenge lifecycle

---

## File Structure

### New Files — Cloudflare Worker (`sticker-ai-proxy/`)

| File | Responsibility |
|------|---------------|
| `sticker-ai-proxy/package.json` | Dependencies (hono, vitest, miniflare) |
| `sticker-ai-proxy/wrangler.toml` | Worker config, D1/R2/KV bindings, cron trigger |
| `sticker-ai-proxy/tsconfig.json` | TypeScript config |
| `sticker-ai-proxy/vitest.config.ts` | Test config with miniflare |
| `sticker-ai-proxy/src/index.ts` | Hono router + cron handler |
| `sticker-ai-proxy/src/routes/auth.ts` | POST /auth/register, POST /auth/refresh |
| `sticker-ai-proxy/src/routes/generate.ts` | POST /generate (AI proxy) |
| `sticker-ai-proxy/src/routes/packs.ts` | Pack CRUD, like, download |
| `sticker-ai-proxy/src/routes/feed.ts` | GET /feed, GET /feed/recent |
| `sticker-ai-proxy/src/routes/challenges.ts` | Challenge list, submit, vote |
| `sticker-ai-proxy/src/routes/profile.ts` | GET /profile/:publicId |
| `sticker-ai-proxy/src/routes/moderation.ts` | Report, block, admin endpoints |
| `sticker-ai-proxy/src/middleware/auth.ts` | JWT verification middleware |
| `sticker-ai-proxy/src/middleware/rateLimit.ts` | KV-based rate limiting |
| `sticker-ai-proxy/src/middleware/promptFilter.ts` | AI prompt blocklist |
| `sticker-ai-proxy/src/db/schema.sql` | D1 CREATE TABLE statements |
| `sticker-ai-proxy/src/utils/jwt.ts` | JWT sign/verify using Web Crypto |
| `sticker-ai-proxy/src/utils/publicId.ts` | Generate short public IDs |
| `sticker-ai-proxy/test/auth.test.ts` | Auth endpoint tests |
| `sticker-ai-proxy/test/packs.test.ts` | Pack endpoint tests |
| `sticker-ai-proxy/test/challenges.test.ts` | Challenge endpoint tests |
| `sticker-ai-proxy/test/moderation.test.ts` | Report/block tests |
| `sticker-ai-proxy/test/generate.test.ts` | AI proxy tests |

### New Files — Flutter App

| File | Responsibility |
|------|---------------|
| `lib/services/api_client.dart` | Central API client, JWT management, all Worker calls |
| `lib/services/auth_service.dart` | Device registration, token storage (secure storage) |
| `lib/data/remote_pack_repository.dart` | Fetch/cache remote packs from Worker |
| `lib/core/widgets/report_button.dart` | Flag icon + report bottom sheet |
| `lib/core/widgets/terms_gate.dart` | Terms acceptance dialog |
| `test/unit/api_client_test.dart` | API client response parsing, errors, retry |
| `test/unit/auth_service_test.dart` | Registration flow, token refresh |
| `test/unit/remote_pack_repository_test.dart` | Catalog, cache, offline |

### New Files — Tooling

| File | Responsibility |
|------|---------------|
| `tool/sticker_manifest.yaml` | Prompt definitions per category/pack |
| `tool/generate_stickers.dart` | Batch AI generation + post-processing |
| `tool/upload_to_r2.sh` | Bulk R2 upload script |
| `tool/seed_challenges.sh` | Seed initial challenges via Worker API |

### New Files — Store Automation

| File | Responsibility |
|------|---------------|
| `fastlane/Gemfile` | Pinned fastlane version |
| `fastlane/Appfile` | App identifiers |
| `fastlane/Fastfile` | Lane definitions |
| `fastlane/Matchfile` | Match cert config |
| `fastlane/metadata/android/en-US/title.txt` | Play Store title |
| `fastlane/metadata/android/en-US/short_description.txt` | Play Store short desc |
| `fastlane/metadata/android/en-US/full_description.txt` | Play Store full desc |
| `.maestro/screenshots/*.yaml` | 8 screenshot flows |
| `.maestro/verification/*.yaml` | 16 verification flows |
| `.github/workflows/release.yml` | Release CI/CD pipeline |

### Modified Files

| File | Change |
|------|--------|
| `pubspec.yaml` | Remove auth/ad deps, add flutter_secure_storage |
| `lib/main.dart` | Remove Firebase TODO, init auth service |
| `lib/data/providers.dart` | Add API client + remote pack providers |
| `lib/services/huggingface_api.dart` | Use Worker URL, parse JSON, remove apiKey |
| `lib/features/auth/presentation/onboarding_screen.dart` | Fix Telegram copy |
| `lib/features/packs/presentation/pack_detail_screen.dart` | Remove Telegram button, add report |
| `lib/features/challenges/presentation/challenges_screen.dart` | Real submit/vote via API |
| `lib/features/feed/presentation/feed_screen.dart` | Real trending from API |
| `lib/features/profile/presentation/profile_screen.dart` | Real stats from API |
| `android/app/build.gradle.kts` | Release signing, R8/ProGuard |
| `android/app/src/main/kotlin/.../StickerContentProvider.kt` | Real privacy/license URLs |
| `.github/workflows/ci.yml` | Disable functions-lint, add worker-ci |
| `.gitignore` | Add key.properties, *.jks |

---

## Phase A: Cloudflare Backend

### Task 1: Worker Project Scaffold

**Files:**
- Create: `sticker-ai-proxy/package.json`
- Create: `sticker-ai-proxy/tsconfig.json`
- Create: `sticker-ai-proxy/wrangler.toml`
- Create: `sticker-ai-proxy/vitest.config.ts`
- Create: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "sticker-ai-proxy",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src/",
    "test": "vitest run"
  },
  "dependencies": {
    "hono": "^4.0.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.0.0",
    "@cloudflare/vitest-pool-workers": "^0.5.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0",
    "eslint": "^9.0.0",
    "@typescript-eslint/eslint-plugin": "^8.0.0",
    "@typescript-eslint/parser": "^8.0.0"
  }
}
```

- [ ] **Step 2: Create wrangler.toml**

```toml
name = "sticker-officer-api"
main = "src/index.ts"
compatibility_date = "2026-03-01"

[triggers]
crons = ["0 * * * *"]  # hourly challenge lifecycle

[[d1_databases]]
binding = "DB"
database_name = "sticker-officer"
database_id = "" # fill after wrangler d1 create

[[r2_buckets]]
binding = "R2"
bucket_name = "sticker-officer-packs"

[[kv_namespaces]]
binding = "KV"
id = "" # fill after wrangler kv create
```

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "types": ["@cloudflare/workers-types"]
  },
  "include": ["src"]
}
```

- [ ] **Step 4: Create vitest.config.ts**

```typescript
import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
      },
    },
  },
});
```

- [ ] **Step 5: Create minimal src/index.ts**

```typescript
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
    // Challenge lifecycle cron — implemented in Task 8
  },
};
```

- [ ] **Step 6: Install dependencies and verify**

Run: `cd sticker-ai-proxy && npm install && npm run typecheck`
Expected: clean compilation

- [ ] **Step 7: Commit**

```bash
git add sticker-ai-proxy/
git commit -m "feat: scaffold Cloudflare Worker project with Hono, D1, R2, KV bindings"
```

---

### Task 2: D1 Schema

**Files:**
- Create: `sticker-ai-proxy/src/db/schema.sql`

- [ ] **Step 1: Create schema.sql**

Copy the full D1 schema from spec section 1.4.2 (devices, packs, stickers, likes, downloads, challenges, challenge_submissions, challenge_votes, reports, blocks — 10 tables).

- [ ] **Step 2: Apply schema locally**

Run: `cd sticker-ai-proxy && wrangler d1 create sticker-officer && wrangler d1 execute sticker-officer --local --file=src/db/schema.sql`
Expected: all 10 tables created

- [ ] **Step 3: Commit**

```bash
git add sticker-ai-proxy/src/db/schema.sql
git commit -m "feat: add D1 schema — 10 tables for social backend"
```

---

### Task 3: JWT Utilities + Auth Routes

**Files:**
- Create: `sticker-ai-proxy/src/utils/jwt.ts`
- Create: `sticker-ai-proxy/src/utils/publicId.ts`
- Create: `sticker-ai-proxy/src/middleware/auth.ts`
- Create: `sticker-ai-proxy/src/routes/auth.ts`
- Create: `sticker-ai-proxy/test/auth.test.ts`
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Write auth test**

```typescript
// test/auth.test.ts
import { describe, it, expect } from 'vitest';
import { SELF } from 'cloudflare:test';

describe('POST /auth/register', () => {
  it('returns JWT and public_id for new device', async () => {
    const res = await SELF.fetch('http://localhost/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: 'test-device-001' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json();
    expect(data.token).toBeDefined();
    expect(data.public_id).toMatch(/^user_[a-z0-9]+$/);
    expect(data.expires_in).toBe(31536000);
  });

  it('returns same public_id for repeat registration', async () => {
    const id = 'test-device-repeat';
    const res1 = await SELF.fetch('http://localhost/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: id }),
    });
    const data1 = await res1.json();

    const res2 = await SELF.fetch('http://localhost/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: id }),
    });
    const data2 = await res2.json();

    expect(data1.public_id).toBe(data2.public_id);
  });

  it('rejects missing device_id', async () => {
    const res = await SELF.fetch('http://localhost/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd sticker-ai-proxy && npm test`
Expected: FAIL — routes not defined

- [ ] **Step 3: Implement jwt.ts**

```typescript
// src/utils/jwt.ts
const encoder = new TextEncoder();

export async function signJwt(
  payload: Record<string, unknown>,
  secret: string,
  expiresInSeconds: number = 31536000
): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const fullPayload = { ...payload, iat: now, exp: now + expiresInSeconds };

  const base64Header = toBase64Url(JSON.stringify(header));
  const base64Payload = toBase64Url(JSON.stringify(fullPayload));
  const data = `${base64Header}.${base64Payload}`;

  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
  const base64Sig = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');

  return `${data}.${base64Sig}`;
}

function toBase64Url(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function fromBase64Url(str: string): string {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  return atob(padded);
}

export async function verifyJwt(
  token: string, secret: string
): Promise<Record<string, unknown> | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, signature] = parts;
  const data = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']
  );

  const sigBytes = Uint8Array.from(fromBase64Url(signature), c => c.charCodeAt(0));
  const valid = await crypto.subtle.verify('HMAC', key, sigBytes, encoder.encode(data));
  if (!valid) return null;

  const decoded = JSON.parse(fromBase64Url(payload));
  if (decoded.exp && decoded.exp < Math.floor(Date.now() / 1000)) return null;

  return decoded;
}
```

- [ ] **Step 4: Implement publicId.ts**

```typescript
// src/utils/publicId.ts
export function generatePublicId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = 'user_';
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  for (const byte of bytes) {
    id += chars[byte % chars.length];
  }
  return id;
}
```

- [ ] **Step 5: Implement auth middleware**

```typescript
// src/middleware/auth.ts
import { Context, Next } from 'hono';
import { verifyJwt } from '../utils/jwt';
import type { Env } from '../index';

export async function requireAuth(c: Context<{ Bindings: Env }>, next: Next) {
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing authorization' }, 401);
  }
  const token = header.slice(7);
  const payload = await verifyJwt(token, c.env.JWT_SECRET);
  if (!payload) {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }

  // Check if device is blocked
  const device = await c.env.DB.prepare(
    'SELECT is_blocked FROM devices WHERE device_id = ?'
  ).bind(payload.did).first();

  if (device?.is_blocked) {
    return c.json({ error: 'Account suspended' }, 403);
  }

  c.set('deviceId', payload.did as string);
  c.set('publicId', payload.pid as string);
  await next();
}

export async function requireTerms(c: Context<{ Bindings: Env }>, next: Next) {
  const deviceId = c.get('deviceId');
  const device = await c.env.DB.prepare(
    'SELECT terms_accepted_at FROM devices WHERE device_id = ?'
  ).bind(deviceId).first();

  if (!device?.terms_accepted_at) {
    return c.json({ error: 'Must accept terms before publishing' }, 403);
  }
  await next();
}
```

- [ ] **Step 6: Implement auth routes**

```typescript
// src/routes/auth.ts
import { Hono } from 'hono';
import { signJwt } from '../utils/jwt';
import { generatePublicId } from '../utils/publicId';
import { requireAuth } from '../middleware/auth';
import type { Env } from '../index';

const auth = new Hono<{ Bindings: Env }>();

auth.post('/register', async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const deviceId = body.device_id;
  if (!deviceId || typeof deviceId !== 'string') {
    return c.json({ error: 'device_id required' }, 400);
  }

  // Check if device already registered
  const existing = await c.env.DB.prepare(
    'SELECT public_id FROM devices WHERE device_id = ?'
  ).bind(deviceId).first();

  let publicId: string;
  if (existing) {
    publicId = existing.public_id as string;
    await c.env.DB.prepare(
      'UPDATE devices SET last_seen = datetime(\'now\') WHERE device_id = ?'
    ).bind(deviceId).run();
  } else {
    publicId = generatePublicId();
    await c.env.DB.prepare(
      'INSERT INTO devices (device_id, public_id) VALUES (?, ?)'
    ).bind(deviceId, publicId).run();
  }

  const token = await signJwt({ did: deviceId, pid: publicId }, c.env.JWT_SECRET);
  return c.json({ token, public_id: publicId, expires_in: 31536000 });
});

auth.post('/refresh', requireAuth, async (c) => {
  const deviceId = c.get('deviceId');
  const publicId = c.get('publicId');
  const token = await signJwt({ did: deviceId, pid: publicId }, c.env.JWT_SECRET);
  return c.json({ token, public_id: publicId, expires_in: 31536000 });
});

auth.post('/accept-terms', requireAuth, async (c) => {
  const deviceId = c.get('deviceId');
  await c.env.DB.prepare(
    'UPDATE devices SET terms_accepted_at = datetime(\'now\') WHERE device_id = ?'
  ).bind(deviceId).run();
  return c.json({ accepted: true });
});

export { auth };
```

- [ ] **Step 7: Wire auth routes into index.ts**

Add to `src/index.ts`:
```typescript
import { auth } from './routes/auth';
import { requireAuth } from './middleware/auth';

app.route('/auth', auth);
```

- [ ] **Step 8: Run tests**

Run: `cd sticker-ai-proxy && npm test`
Expected: all auth tests PASS

- [ ] **Step 9: Commit**

```bash
git add sticker-ai-proxy/
git commit -m "feat: JWT auth — register, refresh, middleware, public ID"
```

---

### Task 4: Pack Routes (CRUD, Like, Download)

**Files:**
- Create: `sticker-ai-proxy/src/routes/packs.ts`
- Create: `sticker-ai-proxy/test/packs.test.ts`
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Write pack tests** — test publish, like/unlike toggle, download tracking, list by author
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement packs.ts** — POST /packs (requireAuth + requireTerms), POST /packs/:id/like (toggle), POST /packs/:id/download, GET /packs (by author)
- [ ] **Step 4: Wire into index.ts**
- [ ] **Step 5: Run tests — expect PASS**
- [ ] **Step 6: Commit** `"feat: pack CRUD — publish, like, download, list"`

---

### Task 5: Feed Routes

**Files:**
- Create: `sticker-ai-proxy/src/routes/feed.ts`
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Implement GET /feed** — top packs by (like_count * 2 + download_count * 3), exclude is_removed, exclude blocked users for authenticated requests. Paginated with `?limit=20&offset=0`.
- [ ] **Step 2: Implement GET /feed/recent** — newest public packs, same exclusions.
- [ ] **Step 3: Write tests, run, verify PASS**
- [ ] **Step 4: Commit** `"feat: feed routes — trending + recent with block filtering"`

---

### Task 6: Challenge Routes

**Files:**
- Create: `sticker-ai-proxy/src/routes/challenges.ts`
- Create: `sticker-ai-proxy/test/challenges.test.ts`
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Write challenge tests** — list by status, submit sticker (requires terms), vote (1 per submission, multiple per challenge), list submissions with vote counts
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement challenges.ts** — GET /challenges, POST /challenges/:id/submit (requireAuth + requireTerms), POST /challenges/:id/vote (requireAuth), GET /challenges/:id/submissions
- [ ] **Step 4: Run tests — expect PASS**
- [ ] **Step 5: Commit** `"feat: challenge routes — list, submit, Reddit-style vote"`

---

### Task 7: AI Generation Proxy

**Files:**
- Create: `sticker-ai-proxy/src/routes/generate.ts`
- Create: `sticker-ai-proxy/src/middleware/promptFilter.ts`
- Create: `sticker-ai-proxy/src/middleware/rateLimit.ts`
- Create: `sticker-ai-proxy/test/generate.test.ts`

- [ ] **Step 1: Write generate test** — valid prompt returns 4 images, blocked prompt returns 400, rate limit returns 429
- [ ] **Step 2: Implement promptFilter.ts** — blocklist of terms (violence, NSFW, etc.), returns 400 if matched
- [ ] **Step 3: Implement rateLimit.ts** — KV counter per device_id, 5 requests/hour, returns 429 if exceeded
- [ ] **Step 4: Implement generate.ts** — requireAuth → promptFilter → rateLimit → call HF API 4 times with different seeds → return base64 PNG array
- [ ] **Step 5: Run tests — expect PASS**
- [ ] **Step 6: Commit** `"feat: AI generation proxy with content moderation + rate limiting"`

---

### Task 8: Challenge Cron + Moderation Routes + Profile

**Files:**
- Create: `sticker-ai-proxy/src/routes/moderation.ts`
- Create: `sticker-ai-proxy/src/routes/profile.ts`
- Create: `sticker-ai-proxy/test/moderation.test.ts`
- Modify: `sticker-ai-proxy/src/index.ts` (scheduled handler)

- [ ] **Step 1: Implement scheduled handler** in index.ts — transition challenges: upcoming→active (starts_at <= now), active→voting (voting_at <= now), voting→completed (ends_at <= now)
- [ ] **Step 2: Implement moderation.ts** — POST /report (requireAuth), POST /block/:publicId (requireAuth), DELETE /block/:publicId, GET /admin/reports (admin key), POST /admin/action (admin key), **POST /admin/challenges (admin key)** — creates new challenge in D1
- [ ] **Step 3: Implement profile.ts** — GET /profile/:publicId — join devices + aggregated pack stats
- [ ] **Step 4: Write tests for moderation** — report creates record, block hides content, admin can action
- [ ] **Step 5: Run all tests — expect PASS**
- [ ] **Step 6: Commit** `"feat: moderation, profile, challenge cron lifecycle"`

---

### Task 9: R2 Sticker Serving

**Files:**
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Add R2 serving route** — `GET /packs/r2/:packId/:sticker` → fetch from R2, return with correct content-type
- [ ] **Step 2: Add catalog.json serving** — `GET /packs/catalog.json` → fetch from R2
- [ ] **Step 3: Test with a manually uploaded test file**
- [ ] **Step 4: Commit** `"feat: R2 sticker + catalog serving"`

---

### Task 10: Worker CI Job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Disable functions-lint job** — comment out or remove
- [ ] **Step 2: Add worker-ci job** — checkout → setup node 20 → npm ci → npm run typecheck → npm run lint → npm test (working-directory: sticker-ai-proxy)
- [ ] **Step 3: Commit** `"ci: add worker-ci job, disable functions-lint"`

---

### Task 11: Deploy Worker

- [ ] **Step 1: Create D1 database** — `wrangler d1 create sticker-officer`
- [ ] **Step 2: Create R2 bucket** — `wrangler r2 bucket create sticker-officer-packs`
- [ ] **Step 3: Create KV namespace** — `wrangler kv namespace create RATE_LIMIT`
- [ ] **Step 4: Update wrangler.toml** with real IDs
- [ ] **Step 5: Set secrets** — `wrangler secret put JWT_SECRET`, `wrangler secret put HF_API_KEY`, `wrangler secret put ADMIN_KEY`
- [ ] **Step 6: Apply D1 schema** — `wrangler d1 execute sticker-officer --file=src/db/schema.sql`
- [ ] **Step 7: Deploy** — `wrangler deploy`
- [ ] **Step 8: Verify** — `curl https://sticker-officer-api.<account>.workers.dev/health`
- [ ] **Step 9: Commit** wrangler.toml with real IDs `"chore: configure deployed Worker bindings"`

---

## Phase B: Flutter App Updates

### Task 12: Remove Unused Deps + Copy Cleanup

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/auth/presentation/onboarding_screen.dart`
- Modify: `lib/features/packs/presentation/pack_detail_screen.dart`
- Modify: `lib/main.dart`
- Modify: `.gitignore`

- [ ] **Step 1: In pubspec.yaml** — comment out `google_sign_in`, `sign_in_with_apple`, `google_mobile_ads`. Add `flutter_secure_storage: ^9.0.0`.
- [ ] **Step 2: In onboarding_screen.dart** — replace "WhatsApp & Telegram" → "WhatsApp". Replace "One-click export to WhatsApp & Telegram" → "One-click export to WhatsApp".
- [ ] **Step 3: In pack_detail_screen.dart** — remove the Telegram export button entirely (the Container with IconButton that shows "Telegram export coming soon!").
- [ ] **Step 4: Search for all "coming soon"** — `grep -rn "coming soon" lib/` — replace or remove each instance.
- [ ] **Step 5: In main.dart** — remove Firebase TODO comment. Will add auth service init in Task 13.
- [ ] **Step 6: In .gitignore** — add `key.properties`, `*.jks`, `*.keystore`.
- [ ] **Step 7: Run flutter pub get && flutter analyze --no-fatal-infos**
- [ ] **Step 8: Run flutter test** — verify existing tests still pass
- [ ] **Step 9: Commit** `"chore: remove v2 deps, fix copy, add gitignore entries"`

---

### Task 13: Auth Service + API Client

**Files:**
- Create: `lib/services/auth_service.dart`
- Create: `lib/services/api_client.dart`
- Create: `test/unit/auth_service_test.dart`
- Create: `test/unit/api_client_test.dart`
- Modify: `lib/data/providers.dart`

- [ ] **Step 1: Write auth_service_test.dart** — test registration stores token, test expired token triggers refresh, test getToken returns cached token
- [ ] **Step 2: Run — expect FAIL**
- [ ] **Step 3: Implement auth_service.dart**

```dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _cachedToken;
  String? _publicId;

  AuthService({required String baseUrl, FlutterSecureStorage? storage})
    : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
      _storage = storage ?? const FlutterSecureStorage();

  Future<void> ensureRegistered() async {
    _cachedToken = await _storage.read(key: 'jwt_token');
    _publicId = await _storage.read(key: 'public_id');
    if (_cachedToken != null) return;

    var deviceId = await _storage.read(key: 'device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(key: 'device_id', value: deviceId);
    }

    final response = await _dio.post('/auth/register', data: {'device_id': deviceId});
    _cachedToken = response.data['token'];
    _publicId = response.data['public_id'];
    await _storage.write(key: 'jwt_token', value: _cachedToken!);
    await _storage.write(key: 'public_id', value: _publicId!);
  }

  Future<String> getToken() async {
    if (_cachedToken == null) await ensureRegistered();
    return _cachedToken!;
  }

  String? get publicId => _publicId;
}
```

- [ ] **Step 4: Implement api_client.dart** — wraps Dio with auth interceptor that adds `Authorization: Bearer` header, auto-refreshes on 401. Methods: `getFeed()`, `likePack(id)`, `publishPack(...)`, `getChallenges()`, `submitChallenge(...)`, `vote(...)`, `report(...)`, `blockUser(...)`, `getProfile(publicId)`.
- [ ] **Step 5: Write api_client_test.dart** — mock Dio responses, test feed parsing, test error handling, test retry on 401
- [ ] **Step 6: Run tests — expect PASS**
- [ ] **Step 7: Add providers** in `lib/data/providers.dart`:

```dart
final authServiceProvider = Provider<AuthService>((ref) {
  const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8787');
  return AuthService(baseUrl: baseUrl);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.read(authServiceProvider);
  const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8787');
  return ApiClient(baseUrl: baseUrl, authService: auth);
});
```

- [ ] **Step 8: Init auth in main.dart** — call `authService.ensureRegistered()` during app startup
- [ ] **Step 9: Commit** `"feat: auth service + API client with JWT management"`

---

### Task 14: Update HuggingFace API Service

**Files:**
- Modify: `lib/services/huggingface_api.dart`
- Modify: `test/unit/huggingface_api_test.dart`

- [ ] **Step 1: Update test** — expect JSON response with `images` array of base64 strings instead of raw bytes
- [ ] **Step 2: Run — expect FAIL**
- [ ] **Step 3: Update huggingface_api.dart** — remove `apiKey` param, change `_baseUrl` to `String.fromEnvironment('API_BASE_URL')`, parse JSON `images` array, decode base64 to `Uint8List`, return `List<Uint8List>` (same interface)
- [ ] **Step 4: Run tests — expect PASS**
- [ ] **Step 5: Commit** `"feat: HuggingFace API now uses Worker proxy, parses base64 JSON"`

---

### Task 15: Remote Pack Repository

**Files:**
- Create: `lib/data/remote_pack_repository.dart`
- Create: `test/unit/remote_pack_repository_test.dart`
- Modify: `lib/data/providers.dart`

- [ ] **Step 1: Write test** — catalog parsing, cache version check, offline fallback returns empty list, retry logic
- [ ] **Step 2: Run — expect FAIL**
- [ ] **Step 3: Implement remote_pack_repository.dart** — fetch catalog.json from Worker, download pack stickers on demand, cache locally in app documents, check catalog version field for invalidation, retry with exponential backoff (3 attempts)
- [ ] **Step 4: Add provider** for remote pack repo
- [ ] **Step 5: Update feed provider** to merge local + remote packs
- [ ] **Step 6: Run tests — expect PASS**
- [ ] **Step 7: Commit** `"feat: remote pack repository with cache + offline fallback"`

---

### Task 16: UGC Moderation UI

**Files:**
- Create: `lib/core/widgets/report_button.dart`
- Create: `lib/core/widgets/terms_gate.dart`
- Modify: `lib/features/packs/presentation/pack_detail_screen.dart`
- Modify: `lib/features/profile/presentation/profile_screen.dart`

- [ ] **Step 1: Implement report_button.dart** — IconButton with flag icon, on tap shows bottom sheet with reason picker (inappropriate, copyright, spam, harassment, other) + optional text field, calls `apiClient.report()`
- [ ] **Step 2: Implement terms_gate.dart** — Dialog with terms text + "I Accept" button, calls `apiClient.acceptTerms()` which hits `POST /auth/accept-terms` (implemented in Task 3). Stores acceptance locally so dialog only shows once.
- [ ] **Step 3: Add report button** to pack_detail_screen.dart (app bar action) and challenge submission cards
- [ ] **Step 4: Add block user option** to profile_screen.dart
- [ ] **Step 5: Add terms gate** before publish flow in my_packs_screen.dart and before challenge submit
- [ ] **Step 6: Run flutter test** — verify no regressions
- [ ] **Step 7: Commit** `"feat: UGC moderation UI — report, block, terms gate"`

---

### Task 17: Update Screens to Use Real API

**Files:**
- Modify: `lib/features/feed/presentation/feed_screen.dart`
- Modify: `lib/features/challenges/presentation/challenges_screen.dart`
- Modify: `lib/features/profile/presentation/profile_screen.dart`
- Modify: `lib/features/search/presentation/search_screen.dart`

- [ ] **Step 1: Update feed_screen.dart** — replace seed data with `apiClient.getFeed()` and `apiClient.getRecent()`, show shimmer while loading, show offline banner if no network
- [ ] **Step 2: Update challenges_screen.dart** — replace hardcoded challenges with `apiClient.getChallenges()`, wire submit button to `apiClient.submitChallenge()`, wire vote to `apiClient.vote()`
- [ ] **Step 3: Update profile_screen.dart** — fetch real stats from `apiClient.getProfile(publicId)`. **Fix all 8 "coming soon" items** in profile settings: replace with real functionality where possible (display_name edit via API, contact email link) or remove the settings row entirely for v1 (premium, notifications, appearance — these are v2 features). Add contact email for moderation appeals in settings.
- [ ] **Step 4: Update search_screen.dart** — search remote packs from API (or filter local+remote catalog)
- [ ] **Step 5: Run flutter test** — fix any broken tests by mocking API client
- [ ] **Step 6: Commit** `"feat: all screens use real Cloudflare API"`

---

### Task 18: Analyzer Cleanup

- [ ] **Step 1: Run `dart fix --apply`**
- [ ] **Step 2: Run `flutter analyze`** — fix remaining issues manually
- [ ] **Step 3: Target: 0 issues**
- [ ] **Step 4: Update `.github/workflows/ci.yml`** — change `flutter analyze --no-fatal-infos` to `flutter analyze`
- [ ] **Step 5: Run `flutter test`** — ensure nothing broke
- [ ] **Step 6: Commit** `"chore: analyzer cleanup — 0 issues, strict CI gate"`

---

### Task 19: App Icons + Splash + Signing

**Files:**
- Modify: `pubspec.yaml` (flutter_launcher_icons + flutter_native_splash config)
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/.../StickerContentProvider.kt`

- [ ] **Step 1: Add flutter_launcher_icons config** in pubspec.yaml, run `dart run flutter_launcher_icons`
- [ ] **Step 2: Add flutter_native_splash config**, run `dart run flutter_native_splash:create`
- [ ] **Step 3: Verify version consistency** — confirm `1.0.0+1` in pubspec.yaml, build.gradle.kts (`versionCode`/`versionName`), and ios/Runner.xcodeproj (`CURRENT_PROJECT_VERSION`/`MARKETING_VERSION`)
- [ ] **Step 4: Generate Android keystore** (interactive — user must run `keytool` command from spec 1.2)
- [ ] **Step 5: Create android/key.properties** (gitignored)
- [ ] **Step 6: Update build.gradle.kts** — load signing from key.properties, enable minifyEnabled + shrinkResources for release
- [ ] **Step 7: iOS signing** — register App ID `com.futureatoms.stickerOfficer` in Apple Developer portal, set Team ID in `ios/Runner.xcodeproj/project.pbxproj`, run `fastlane match appstore` from fastlane/ directory
- [ ] **Step 8: Create ios/ExportOptions.plist** — specify method (app-store), teamID, provisioningProfiles for the bundle ID
- [ ] **Step 9: Update StickerContentProvider.kt** — real privacy_policy_url, license_agreement_url, publisher_email
- [ ] **Step 10: Build Android release** — `flutter build appbundle --release`
- [ ] **Step 11: Build iOS release** — `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist`
- [ ] **Step 12: Commit** `"feat: app icons, splash, signing (Android + iOS), version verified"`

---

### Task 20: Privacy Policy + Legal

**Files:**
- Create: `docs/legal/privacy-policy.md`
- Create: `docs/legal/terms.md`

- [ ] **Step 1: Write privacy policy** covering AI prompts, device UUID, Cloudflare storage, rate limiting
- [ ] **Step 2: Write terms of service** covering UGC responsibilities, content moderation, acceptable use
- [ ] **Step 3: Deploy to GitHub Pages or Cloudflare Pages** (user decision)
- [ ] **Step 4: Commit** `"docs: privacy policy + terms of service"`

---

## Phase C: Sticker Content Pipeline

### Task 21: Sticker Manifest + Generation Script

**Files:**
- Create: `tool/sticker_manifest.yaml`
- Create: `tool/generate_stickers.dart`

- [ ] **Step 1: Create sticker_manifest.yaml** — 27 packs across 15 categories, 30 prompts each. All prompts original, non-branded. Example:

```yaml
categories:
  - name: "Reaction Memes"
    packs:
      - id: "reaction-memes-1"
        name: "Reaction Memes Vol. 1"
        prompts:
          - "surprised cartoon face with wide eyes and open mouth"
          - "laughing cartoon character holding belly"
          # ... 28 more
```

- [ ] **Step 2: Create generate_stickers.dart** — reads manifest, calls HF API, resizes with `image` package, removes background via HF BRIA-RMBG-2.0, converts to WebP via `cwebp` CLI, validates 30+1 per pack
- [ ] **Step 3: Test with 1 pack** — `dart run tool/generate_stickers.dart --pack=reaction-memes-1`
- [ ] **Step 4: Commit** `"feat: sticker generation pipeline — manifest + script"`

---

### Task 22: R2 Upload + D1 Seeding

**Files:**
- Create: `tool/upload_to_r2.sh`
- Create: `tool/seed_challenges.sh`

- [ ] **Step 1: Generate all 27 packs** — `dart run tool/generate_stickers.dart`
- [ ] **Step 2: Create upload_to_r2.sh** — iterates output directory, uploads each file with `wrangler r2 object put`
- [ ] **Step 3: Run upload** — `bash tool/upload_to_r2.sh`
- [ ] **Step 4: Seed challenges** — create 3 initial challenges via `POST /admin/challenges` (admin key auth): 1 active, 1 upcoming, 1 voting. Use `tool/seed_challenges.sh` with `curl` calls.
- [ ] **Step 5: Verify** — curl Worker feed endpoint, confirm packs appear
- [ ] **Step 6: Commit** `"feat: R2 upload + D1 seeded with 27 packs + 3 challenges"`

---

## Phase D: Store Automation

### Task 23: Fastlane Setup

**Files:**
- Create: `fastlane/Gemfile`
- Create: `fastlane/Appfile`
- Create: `fastlane/Fastfile`
- Create: `fastlane/Matchfile`

- [ ] **Step 1: Create Gemfile** — `gem 'fastlane', '~> 2.232'`
- [ ] **Step 2: Create Appfile** — app_identifier, apple_id, team_id
- [ ] **Step 3: Create Fastfile** — android_build, android_deploy (supply), ios_build (match + flutter build ipa), ios_deploy (deliver) lanes
- [ ] **Step 4: Create Matchfile** — git_url, type, app_identifier
- [ ] **Step 5: Run `bundle install`** in fastlane/
- [ ] **Step 6: Commit** `"feat: Fastlane setup — Gemfile, Appfile, Fastfile, Matchfile"`

---

### Task 24: Store Metadata + Feature Graphic

**Files:**
- Create: `fastlane/metadata/android/en-US/title.txt` — "StickerOfficer - AI Sticker Maker"
- Create: `fastlane/metadata/android/en-US/short_description.txt` — 80 chars
- Create: `fastlane/metadata/android/en-US/full_description.txt` — 4000 chars
- Create: `fastlane/metadata/android/en-US/changelogs/default.txt`

- [ ] **Step 1: Write Android metadata files** with accurate copy (no overstatement)
- [ ] **Step 2: Write iOS metadata** — separate description (no WhatsApp "one-tap export" claim), keywords, promotional_text. iOS captions differ from Android per spec section 3.3 (screenshots 4 and 5 have iOS-specific captions).
- [ ] **Step 3: Create feature graphic** (1024x500) using app branding (coral-to-purple gradient + app icon + tagline)
- [ ] **Step 4: Complete Google Play Data Safety questionnaire** (disclose: AI prompt sending, device ID, IP rate limiting)
- [ ] **Step 5: Complete Apple App Privacy details** (disclose: AI usage, identifiers)
- [ ] **Step 6: Commit** `"feat: store metadata (Android + iOS) + feature graphic"`

---

### Task 25: Maestro Screenshot Flows

**Files:**
- Create: `.maestro/config.yaml`
- Create: `.maestro/utils/navigate_past_onboarding.yaml`
- Create: `.maestro/screenshots/01_feed.yaml` through `08_bulk_edit.yaml`

- [ ] **Step 1: Create config.yaml** — appId
- [ ] **Step 2: Create onboarding skip flow**
- [ ] **Step 3: Create 8 screenshot flows** — each navigates to screen, takes screenshot
- [ ] **Step 4: Test on emulator** — `maestro test .maestro/screenshots/`
- [ ] **Step 5: Copy outputs to Fastlane metadata directories**
- [ ] **Step 6: Commit** `"feat: Maestro screenshot flows for both stores"`

---

### Task 26: Maestro Verification Suite

**Files:**
- Create: `.maestro/verification/01_onboarding.yaml` through `16_like_download.yaml`
- Create: `.maestro/verification/run_all.yaml`

- [ ] **Step 1: Create 16 verification flows** covering every feature
- [ ] **Step 2: Create run_all.yaml** orchestrator
- [ ] **Step 3: Run on emulator** — `maestro test .maestro/verification/run_all.yaml`
- [ ] **Step 4: Commit** `"feat: Maestro verification suite — 16 feature flows"`

---

### Task 27: Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create release.yml** — copy from spec section 5.2 (android-release + ios-release jobs with bundle exec fastlane, proper working dirs, key.properties write step)
- [ ] **Step 2: Verify syntax** — `act -l` or YAML lint
- [ ] **Step 3: Commit** `"ci: release workflow — Play Store + App Store via Fastlane"`

---

## Final: Pre-Submission Verification

### Task 28: Full Verification

- [ ] **Step 1: Run `flutter test`** — all tests pass
- [ ] **Step 2: Run `flutter analyze`** — 0 issues
- [ ] **Step 3: Run `npm test` in sticker-ai-proxy/** — all Worker tests pass
- [ ] **Step 4: Build Android** — `flutter build appbundle --release`
- [ ] **Step 5: Build iOS** — `flutter build ipa --release` (requires signing)
- [ ] **Step 6: Run Maestro verification** on real Android device
- [ ] **Step 7: Manual WhatsApp test** — create pack → export → verify in WhatsApp
- [ ] **Step 8: Review pre-submission checklist** from spec
- [ ] **Step 9: Tag release** — `git tag v1.0.0 && git push --tags`
