# StickerOfficer Production Launch Design

**Date:** 2026-03-22
**Status:** Approved (rev 5 — signed session tokens, UGC moderation, public ID separation)
**Scope:** v1.0.0 launch on Play Store and App Store

## Decisions

- **No Firebase in v1** — Cloudflare (Worker + D1 + R2 + KV) is the full backend. Firebase + auth accounts in v2.
- **No ads in v1** — ship clean, add AdMob in v1.1. Remove `google_mobile_ads` dep.
- **Anonymous identity via signed session tokens** — no email/password auth, but server-issued JWTs prevent spoofing. Remove `google_sign_in` and `sign_in_with_apple` deps. Re-add in v2.
- **All social features are real** — challenges, feed, likes, downloads, voting all backed by Cloudflare D1. No fake demo data. No "coming soon" placeholders.
- **UGC moderation required for both stores** — report, block, terms acceptance, admin moderation queue. Required by Apple Guideline 1.2 and Google Play UGC policy.
- **Challenge voting: Reddit-style** — vote on as many submissions as you want, once per submission.
- **AI enabled via Cloudflare Worker** — returns 4 PNG images per request (matching existing app contract). Workers Paid plan ($5/month) required for D1 + KV + higher quotas.
- **Sticker content served from Cloudflare R2** — 5 bundled packs + 22 remote packs, WebP for WhatsApp
- **Maestro (>= 2.x stable) + Fastlane** for screenshots and store submission
- **iOS WhatsApp** is share-sheet only — iOS store copy reflects this accurately
- **Play Store first**, App Store second
- **iPad supported in v1** — iPad screenshots required
- **Accepted risk:** No crash reporting in v1. Add Sentry or Crashlytics in v1.1.

---

## Phase 0: UX Copy Cleanup

All placeholder copy and unbuilt features must become real or be removed. No "coming soon" anywhere.

### 0.1 Onboarding Screen

**File:** `lib/features/auth/presentation/onboarding_screen.dart`

| Current | Fix |
|---------|-----|
| "Share on WhatsApp & Telegram" | "Share on WhatsApp" |
| "One-click export to WhatsApp & Telegram" | "One-click export to WhatsApp" |
| "Join the Community" / "share with the world" | Keep — this is now real. Users can publish packs, join challenges, vote. |

### 0.2 Pack Detail Screen

**File:** `lib/features/packs/presentation/pack_detail_screen.dart`

| Current | Fix |
|---------|-----|
| Telegram button → "coming soon!" | Remove Telegram button entirely. Add back in v2. |

### 0.3 Challenges Screen

**File:** `lib/features/challenges/presentation/challenges_screen.dart`

All challenge actions become real:
- "Submit" → uploads sticker to D1 challenge submissions
- "Vote" → records vote in D1
- Challenge lifecycle (upcoming → active → voting → completed) managed by Worker cron

### 0.4 Full "Coming Soon" Audit

Search codebase for "coming soon" — every instance either becomes a working feature or gets removed.

---

## Phase 1: Production Hardening

### 1.1 App Icons

- `flutter_launcher_icons` for all Android/iOS sizes from single source image
- `flutter_native_splash` for branded splash (coral-to-purple gradient)

### 1.2 Android Release Signing

- Generate keystore: `keytool -genkey -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000 -storepass <password>`
- Create `android/key.properties` (gitignored)
- **Add `key.properties` and `*.jks` to `.gitignore`**
- Update `build.gradle.kts`: load signing from `key.properties`, enable `minifyEnabled = true` and `shrinkResources = true`
- Enable Play App Signing in Google Play Console

### 1.3 iOS Signing

- Register App ID `com.futureatoms.stickerOfficer` in Apple Developer portal
- Set Team ID in `project.pbxproj`
- **Use Fastlane `match` exclusively** (private Git repo). No raw .p12 secrets.

### 1.4 Cloudflare Backend (Worker + D1 + R2 + KV)

**Requires: Cloudflare Workers Paid plan ($5/month)** for D1, KV, and higher request quotas.

```
sticker-ai-proxy/
├── package.json
├── wrangler.toml
├── tsconfig.json
├── src/
│   ├── index.ts          # Router + middleware
│   ├── routes/
│   │   ├── auth.ts       # Device registration + JWT issuance
│   │   ├── generate.ts   # AI generation (POST /generate)
│   │   ├── packs.ts      # Pack catalog + likes + downloads
│   │   ├── feed.ts       # Trending feed
│   │   ├── challenges.ts # Challenge CRUD + submissions + voting
│   │   ├── profile.ts    # Anonymous user profile
│   │   └── moderation.ts # Report + block + admin review
│   ├── middleware/
│   │   ├── auth.ts       # JWT verification middleware
│   │   ├── rateLimit.ts  # KV-based per-IP rate limiting
│   │   └── moderation.ts # Prompt content moderation blocklist
│   └── db/
│       └── schema.sql    # D1 schema
├── test/
│   └── *.test.ts         # Worker unit tests
└── vitest.config.ts
```

#### 1.4.1 Anonymous Identity Model (Signed Session Tokens)

Client-asserted device IDs are spoofable. Instead, the Worker issues signed JWTs:

**Registration flow (first app launch):**
1. App generates a device UUID locally
2. App calls `POST /auth/register` with `{ "device_id": "<uuid>" }`
3. Worker creates a `devices` row, generates a `public_id` (e.g., `user_abc123`), and returns a signed JWT:
   ```json
   { "token": "eyJ...", "public_id": "user_abc123", "expires_in": 31536000 }
   ```
4. JWT payload: `{ "did": "<device_id>", "pid": "user_abc123", "iat": ..., "exp": ... }`
5. JWT signed with a Worker secret (`wrangler secret put JWT_SECRET`) using HS256 via Web Crypto API
6. App stores token in SharedPreferences. Refreshes via `POST /auth/refresh` before expiry.

**All authenticated requests** use `Authorization: Bearer <jwt>`. Worker middleware verifies signature before processing.

**Public ID separation:** `public_id` (e.g., `user_abc123`) is used in profile URLs and displayed publicly. Internal `device_id` is never exposed in API responses or URLs.

#### 1.4.2 D1 Schema

```sql
CREATE TABLE devices (
  device_id TEXT PRIMARY KEY,
  public_id TEXT UNIQUE NOT NULL,     -- short public identifier, never exposes device_id
  display_name TEXT,
  terms_accepted_at TEXT,             -- must accept before first publish
  is_blocked BOOLEAN DEFAULT FALSE,   -- admin can block abusive users
  packs_created INTEGER DEFAULT 0,
  total_likes_received INTEGER DEFAULT 0,
  first_seen TEXT DEFAULT (datetime('now')),
  last_seen TEXT DEFAULT (datetime('now'))
);

CREATE TABLE packs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  author_device_id TEXT NOT NULL REFERENCES devices(device_id),
  category TEXT,
  sticker_count INTEGER DEFAULT 0,
  like_count INTEGER DEFAULT 0,
  download_count INTEGER DEFAULT 0,
  is_public BOOLEAN DEFAULT FALSE,
  is_removed BOOLEAN DEFAULT FALSE,   -- admin moderation flag
  tags TEXT, -- JSON array
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE stickers (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  r2_key TEXT NOT NULL,
  position INTEGER DEFAULT 0
);

CREATE TABLE likes (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  pack_id TEXT NOT NULL REFERENCES packs(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, pack_id)
);

CREATE TABLE downloads (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  pack_id TEXT NOT NULL REFERENCES packs(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, pack_id)
);

CREATE TABLE challenges (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  theme TEXT NOT NULL,
  status TEXT DEFAULT 'upcoming', -- upcoming, active, voting, completed
  starts_at TEXT NOT NULL,
  voting_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE challenge_submissions (
  id TEXT PRIMARY KEY,
  challenge_id TEXT NOT NULL REFERENCES challenges(id),
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  sticker_r2_key TEXT NOT NULL,
  vote_count INTEGER DEFAULT 0,
  is_removed BOOLEAN DEFAULT FALSE,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Reddit-style voting: one vote per device per submission.
-- A device can vote on multiple submissions in the same challenge.
CREATE TABLE challenge_votes (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  submission_id TEXT NOT NULL REFERENCES challenge_submissions(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, submission_id)
);

-- UGC moderation: content reports
CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  reporter_device_id TEXT NOT NULL REFERENCES devices(device_id),
  target_type TEXT NOT NULL,          -- 'pack', 'sticker', 'submission', 'user'
  target_id TEXT NOT NULL,            -- ID of the reported entity
  reason TEXT NOT NULL,               -- 'inappropriate', 'copyright', 'spam', 'harassment', 'other'
  details TEXT,                       -- optional free-text from reporter
  status TEXT DEFAULT 'pending',      -- pending, reviewed, actioned, dismissed
  reviewed_at TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Per-device block list (user blocks another user)
CREATE TABLE blocks (
  blocker_device_id TEXT NOT NULL REFERENCES devices(device_id),
  blocked_device_id TEXT NOT NULL REFERENCES devices(device_id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (blocker_device_id, blocked_device_id)
);
```

#### 1.4.3 API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/auth/register` | none | Register device, get JWT + public_id |
| `POST` | `/auth/refresh` | JWT | Refresh expiring token |
| `POST` | `/generate` | JWT | AI generation (4 PNG images) |
| `GET` | `/packs/catalog.json` | none | R2 seed pack catalog |
| `GET` | `/feed` | none | Trending packs (excludes blocked users' content for authed requests) |
| `GET` | `/feed/recent` | none | Recently published packs |
| `POST` | `/packs` | JWT + terms | Publish pack (requires terms_accepted_at). Blocked users get 403. |
| `POST` | `/packs/:id/like` | JWT | Like/unlike a pack |
| `POST` | `/packs/:id/download` | JWT | Track download |
| `GET` | `/challenges` | none | List challenges by status |
| `POST` | `/challenges/:id/submit` | JWT + terms | Submit sticker (requires terms). Blocked users get 403. |
| `POST` | `/challenges/:id/vote` | JWT | Vote on submission (1 per submission, unlimited per challenge) |
| `GET` | `/challenges/:id/submissions` | none | List submissions + vote counts |
| `GET` | `/profile/:publicId` | none | Public profile (uses public_id, not device_id) |
| `POST` | `/report` | JWT | Report a pack, sticker, submission, or user |
| `POST` | `/block/:publicId` | JWT | Block a user (hide their content from your feed) |
| `DELETE` | `/block/:publicId` | JWT | Unblock a user |
| `GET` | `/admin/reports` | admin key | List pending reports (admin only) |
| `POST` | `/admin/action` | admin key | Remove content or block user (admin only) |
| `GET` | `/packs/r2/{pack-id}/{sticker}.webp` | none | Serve sticker from R2 |

#### 1.4.4 UGC Moderation (Required by Apple 1.2 + Google Play UGC Policy)

**In-app surfaces (Flutter):**
- Report button (flag icon) on every pack, sticker, and challenge submission
- Report reason picker: inappropriate, copyright, spam, harassment, other
- Block user option on profile and pack screens (hides all their content)
- Terms of Service acceptance gate before first publish or challenge submit
- Contact email visible in settings for moderation appeals

**Server-side (Worker):**
- Reports stored in D1 `reports` table
- Admin endpoint (`/admin/reports`) to review pending reports (protected by admin API key)
- Admin action endpoint to remove content (`is_removed = TRUE`) or block users (`is_blocked = TRUE`)
- Blocked users cannot publish, submit, or like (JWT middleware checks `is_blocked`)
- Removed content hidden from feed, search, and challenge listings
- App Store review notes: document moderation flow, contact email, and admin tools

**Operational:**
- Check reports daily (manual for v1 — admin endpoint accessed via curl or simple web UI)
- Escalation: if report volume exceeds manual capacity, add automated heuristics in v1.1

**AI Generation Contract:**
```
POST /generate
Headers: Authorization: Bearer <jwt>
Request:  { "prompt": "cute cat", "count": 4 }
Response: { "images": ["base64png1", "base64png2", "base64png3", "base64png4"] }
```

**App-side changes in `lib/services/huggingface_api.dart`:**
- Remove `apiKey` parameter
- Change `_baseUrl` to Worker URL
- Parse JSON response (decode base64 `images` array)
- Keep returning `List<Uint8List>` — same interface
- Worker URL via `--dart-define=API_BASE_URL=https://sticker-ai.futureatoms.workers.dev`

**New app-side service: `lib/services/api_client.dart`:**
- On first launch: call `POST /auth/register` with device UUID → store JWT + public_id in SharedPreferences
- All subsequent requests: `Authorization: Bearer <jwt>` header
- Auto-refresh JWT before expiry
- Wraps all Worker API calls (feed, challenges, likes, packs, profile, report, block)
- Handles offline gracefully (fall back to local data)

**New app-side UI for UGC moderation:**
- `lib/core/widgets/report_button.dart` — flag icon, triggers report bottom sheet
- `lib/core/widgets/terms_gate.dart` — terms acceptance dialog shown before first publish/submit
- Block user option in pack detail and profile screens

### 1.5 Remove Unused v2 Dependencies

- Keep Firebase deps commented in `pubspec.yaml`
- **Remove:** `google_sign_in`, `sign_in_with_apple`, `google_mobile_ads`
- Replace Firebase TODO in `main.dart` with clean init for device UUID
- **Disable `functions-lint` CI job** — Cloud Functions not in v1

### 1.6 WhatsApp Provider Metadata

Replace example URLs in `StickerContentProvider.kt`:
- `privacy_policy_url` → real URL
- `license_agreement_url` → real URL
- `publisher_email` → real email

### 1.7 Privacy Policy & Support Page

Privacy policy must disclose:
- AI prompts sent to Hugging Face via Cloudflare proxy
- IP addresses processed for rate limiting
- Device UUID used for anonymous identification (not linked to personal identity)
- Pack publishing stores sticker images and metadata on Cloudflare
- Challenge submissions and votes stored on Cloudflare

### 1.8 Analyzer Cleanup

- `dart fix --apply` → manual fix remaining → target 0 issues
- **Sequence:** Fix issues first, THEN tighten CI gate

### 1.9 Version & Build Number

- `1.0.0+1` confirmed across all configs
- CI: `--build-number=${{ github.run_number }}` for auto-increment

---

## Phase 2: Sticker Content Pipeline

### 2.1 Generation

- HF Inference API (SDXL/SD3) for batch generation
- **All prompts must be original, non-branded content.** No celebrities, trademarks, copyrighted characters.
- Script: `tool/generate_stickers.dart` **(new file)**
  - Reads `tool/sticker_manifest.yaml`
  - Calls HF API → resize 512×512 → background removal (HF BRIA-RMBG-2.0) → convert to WebP (`cwebp`)
  - Validates: exactly 30 stickers + 1 tray icon (96×96) per pack. Fails if wrong.
- Bulk upload: `tool/upload_to_r2.sh` (scripted, not manual)
- **After R2 upload, seed D1 with pack metadata** via Worker API (`POST /packs` for each)

### 2.2 Catalog Schema

```json
{
  "version": 1,
  "updatedAt": "2026-03-22T00:00:00Z",
  "packs": [
    {
      "id": "reaction-memes-1",
      "name": "Reaction Memes Vol. 1",
      "category": "reactions",
      "stickerCount": 30,
      "trayIcon": "reaction-memes-1/tray.webp",
      "stickers": ["01.webp", "02.webp", "..."],
      "tags": ["reaction", "lol", "omg", "facepalm"],
      "author": "StickerOfficer",
      "sizeBytes": 1245000,
      "previewUrl": "reaction-memes-1/01.webp"
    }
  ]
}
```

Contract shared between: generation script, Worker, and `remote_pack_repository.dart`.

### 2.3 Categories (27 packs, ~810 stickers)

| # | Category | Packs | Stickers | IP Notes |
|---|----------|-------|----------|----------|
| 1 | Reaction Memes | 3 | 90 | Original cartoon faces only |
| 2 | Brainrot / Gen-Z Slang | 2 | 60 | Text + original characters |
| 3 | Wholesome / Love / Friendship | 2 | 60 | Original cute characters |
| 4 | Daily Life / Relatable | 2 | 60 | Generic scenes |
| 5 | Cute Animals | 3 | 90 | Original cartoon animals |
| 6 | Emoji Remix / Mashups | 2 | 60 | Original emoji-style faces only |
| 7 | Food & Drinks | 1 | 30 | Generic food |
| 8 | Motivational / Hustle | 1 | 30 | Original typography |
| 9 | Desi Culture | 2 | 60 | Original characters, no celebrities |
| 10 | Kawaii / Cute Art | 2 | 60 | Original kawaii style |
| 11 | Sports & Fitness | 1 | 30 | Generic athletes, no logos |
| 12 | Work / Office Life | 1 | 30 | Generic scenes |
| 13 | Festivals / Celebrations | 2 | 60 | Generic celebrations |
| 14 | Gaming | 1 | 30 | Generic scenes, no game IPs |
| 15 | Good Morning / Night / Birthday | 2 | 60 | Greeting stickers |

### 2.4 R2 Storage

WebP format, 512×512, <100KB each. Tray icons 96×96, <50KB. ~50MB total.

### 2.5 Bundled vs. Remote

- **Bundled:** 5 packs (150 stickers) — immediate offline
- **Remote:** 22 packs (~660 stickers) — downloaded on demand from Worker/R2

### 2.6 App-Side Changes

- New `lib/data/remote_pack_repository.dart`
- New `lib/services/api_client.dart` (central API client for all Worker endpoints)
- Update `providers.dart` to merge local + remote packs, fetch feed from API
- Update `challenges_screen.dart` to use real API (submit, vote, fetch)
- Update `feed_screen.dart` to fetch real trending from API
- Update `profile_screen.dart` to fetch real stats from API
- **Offline handling:** bundled packs always available, API-dependent features show "Connect to internet" banner

### 2.7 Required Unit Tests for New Code

- `test/unit/api_client_test.dart` — Worker response parsing, error handling, retry logic
- `test/unit/remote_pack_repository_test.dart` — catalog parsing, cache versioning, partial download retry, offline fallback
- `test/unit/huggingface_api_test.dart` — update existing tests for new JSON response format (base64 images array)
- Worker-side: `sticker-ai-proxy/test/` — endpoint tests with miniflare

---

## Phase 3: Store Screenshot Automation

### 3.1 Tools

- Maestro (>= 2.x stable) for screenshot capture
- Fastlane `supply` + `deliver` for store upload
- **Play Store:** Raw screenshots, no device frames (Google recommends against)
- **App Store:** Fastlane `frameit` for device frames + captions

### 3.2 Screenshot Targets

**Android (Play Store) — no device frames:**
- Phone: Pixel 7 Pro (1080×2400)

**iOS (App Store) — with frameit:**
- 6.7" iPhone 15 Pro Max: 1290×2796
- 6.1" iPhone 15 Pro: 1179×2556
- 5.5" iPhone 8 Plus: 1242×2208
- 12.9" iPad Pro: 2048×2732 **(required)**
- 11" iPad Pro: 1668×2388 (recommended)

### 3.3 Platform-Specific Captions

| # | Screen | Android | iOS |
|---|--------|---------|-----|
| 1 | Feed | "Discover trending stickers" | "Discover trending stickers" |
| 2 | Editor | "Create custom stickers with powerful tools" | "Create custom stickers with powerful tools" |
| 3 | AI Generate | "AI-powered sticker creation" | "AI-powered sticker creation" |
| 4 | My Packs | "Organize & export to WhatsApp in one tap" | "Organize & share your sticker packs" |
| 5 | Pack Detail | "Add sticker packs directly to WhatsApp" | "Share stickers with friends" |
| 6 | Search | "Browse hundreds of stickers" | "Browse hundreds of stickers" |
| 7 | Challenges | "Join sticker challenges" | "Join sticker challenges" |
| 8 | Bulk Edit | "Edit multiple stickers at once" | "Edit multiple stickers at once" |

### 3.4 Fastlane Directory Structure

Using **Fastlane's default expected paths** to avoid custom path configuration:

```
fastlane/
├── Appfile               # app_identifier, apple_id, team_id
├── Fastfile              # Lane definitions
├── Gemfile               # gem 'fastlane' (pinned version)
├── Gemfile.lock
├── Matchfile             # match config
├── metadata/
│   └── android/
│       └── en-US/
│           ├── title.txt
│           ├── short_description.txt
│           ├── full_description.txt
│           ├── changelogs/
│           │   └── default.txt
│           └── images/
│               ├── phoneScreenshots/    # ← Maestro output
│               ├── icon.png
│               └── featureGraphic.png
└── screenshots/          # ← deliver default for iOS
    └── en-US/
        ├── iPhone 15 Pro Max/
        ├── iPhone 15 Pro/
        ├── iPhone 8 Plus/
        ├── iPad Pro (12.9-inch)/
        └── iPad Pro (11-inch)/
```

**Note:** `supply` expects metadata under `fastlane/metadata/android/en-US/`. `deliver` expects iOS screenshots under `fastlane/screenshots/en-US/`. Using defaults — no custom path overrides needed.

---

## Phase 4: Local Testing & Feature Verification

### 4.1 Local LAN Hub

Already at `tool/local_release_hub.dart`. Additions:
- iOS: use `flutter run --release` on plugged-in device (simpler than OTA/HTTPS)
- QR code for Android APK download

### 4.2 Maestro Verification Suite

```
.maestro/verification/
├── 01_onboarding.yaml
├── 02_feed_navigation.yaml
├── 03_create_pack.yaml
├── 04_editor_tools.yaml
├── 05_ai_generate.yaml
├── 06_add_to_pack.yaml
├── 07_publish_pack.yaml          # NEW: publish to Worker API
├── 08_whatsapp_export.yaml
├── 09_search.yaml
├── 10_challenges_submit.yaml     # NEW: real submission
├── 11_challenges_vote.yaml       # NEW: real voting
├── 12_profile.yaml
├── 13_bulk_edit.yaml
├── 14_video_to_sticker.yaml
├── 15_ipad_layout.yaml
├── 16_like_download.yaml         # NEW: like + download tracking
└── run_all.yaml
```

### 4.3 Testing Order

1. Android phone → Maestro → manual WhatsApp test
2. iOS phone → `flutter run --release` → Maestro → share-sheet test
3. iPad → layout verification + screenshots

---

## Phase 5: Store Submission Pipeline (CI/CD)

### 5.1 CI Jobs

**Existing `.github/workflows/ci.yml`:**
- `analyze-and-test` — Flutter lint + tests (keep)
- `functions-lint` — **disable** (Firebase not in v1)
- **Add `worker-ci`** — lint + typecheck + test the Cloudflare Worker

```yaml
  worker-ci:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: sticker-ai-proxy
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run typecheck
      - run: npm run lint
      - run: npm test
```

### 5.2 Release Workflow

`.github/workflows/release.yml` triggered on `v*` tags:

```yaml
name: Release Pipeline
on:
  push:
    tags: ['v*']

jobs:
  android-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.2'
          cache: true
      - run: flutter pub get
      - run: flutter test
      - run: flutter analyze
      - name: Decode keystore
        run: echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > android/upload-keystore.jks
      - name: Write key.properties
        run: echo "${{ secrets.ANDROID_KEY_PROPERTIES }}" > android/key.properties
      - name: Build AAB
        run: flutter build appbundle --release --build-number=${{ github.run_number }} --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL }}
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.2' }
      - run: bundle install
        working-directory: fastlane
      - run: bundle exec fastlane supply --aab ../build/app/outputs/bundle/release/app-release.aab --track internal --json-key-data '${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}'
        working-directory: fastlane

  ios-release:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.2'
          cache: true
      - run: flutter pub get
      - run: flutter test
      - run: flutter analyze
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.2' }
      - run: bundle install
        working-directory: fastlane
      - name: Match certificates
        run: bundle exec fastlane match appstore --readonly
        working-directory: fastlane
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
      - name: Build IPA
        run: flutter build ipa --release --build-number=${{ github.run_number }} --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL }} --export-options-plist=ios/ExportOptions.plist
      - name: Upload to App Store Connect
        run: bundle exec fastlane deliver --ipa ../build/ios/ipa/Runner.ipa --skip_metadata --skip_screenshots
        working-directory: fastlane
        env:
          APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY }}
```

**Key fixes from review:**
- `bundle install` + `bundle exec fastlane` (reproducible, uses Gemfile)
- `working-directory: fastlane` (paths resolve correctly for supply/deliver)
- `android/key.properties` explicitly written before build
- IPA path: `Runner.ipa` (matches Xcode product name)

### 5.3 Secrets

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | Release keystore |
| `ANDROID_KEY_PROPERTIES` | key.properties content |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Console API |
| `API_BASE_URL` | Cloudflare Worker URL |
| `MATCH_PASSWORD` | iOS cert encryption (match only) |
| `MATCH_GIT_URL` | Private cert repo (match only) |
| `ASC_KEY_ID` | App Store Connect key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_API_KEY` | App Store Connect private key |

### 5.4 Rollback Plan

Rejected → fix on main → tag `v1.0.1` → CI re-builds → re-submit.

### 5.5 Submission Order

1. Google Play internal testing
2. TestFlight (parallel)
3. Play Store production
4. App Store production

---

## Content Moderation

Cloudflare Worker:
- Prompt blocklist (violence, NSFW, hate speech)
- Rate limit: 5 generate req/IP/hour (KV counter)
- Log prompt hashes only (no raw prompt storage)
- Document in App Store review notes

---

## Pre-Submission Checklist

- [ ] No "coming soon" text anywhere in the app
- [ ] Telegram button removed
- [ ] All social features work against real Cloudflare D1 data
- [ ] All tests pass (974+ existing + new unit tests for API client, remote repo, Worker)
- [ ] `flutter analyze` clean (0 issues)
- [ ] `.gitignore` includes `key.properties` and `*.jks`
- [ ] Auth/ad deps removed from pubspec.yaml
- [ ] Android keystore + Play App Signing configured
- [ ] R8/ProGuard enabled for release
- [ ] iOS certs via `match`
- [ ] Cloudflare Workers Paid plan active
- [ ] Worker deployed (auth + AI + social API + sticker CDN + UGC moderation + reporting)
- [ ] JWT_SECRET configured as Worker secret
- [ ] Worker CI job added and passing
- [ ] D1 schema applied (devices, packs, stickers, likes, downloads, challenges, submissions, votes, reports, blocks)
- [ ] D1 seeded with initial challenge data
- [ ] Anonymous identity flow tested (register → JWT → authenticated requests)
- [ ] Report flow tested (report button → D1 → admin review endpoint)
- [ ] Block flow tested (block user → content hidden)
- [ ] Terms acceptance gate before publish/submit
- [ ] R2 sticker packs uploaded (22 packs, ~660 WebP stickers)
- [ ] catalog.json validated (30 stickers + tray per pack)
- [ ] All sticker prompts IP-safe
- [ ] Maestro screenshots for phone + iPad
- [ ] Play: no device frames. App Store: frameit device frames.
- [ ] iOS captions do NOT overstate WhatsApp
- [ ] Fastlane metadata in correct default paths (android/ for supply, screenshots/ for deliver)
- [ ] Gemfile pinned, CI uses `bundle exec`
- [ ] Privacy policy live (AI, device UUID, Cloudflare storage)
- [ ] Support URL live
- [ ] WhatsApp provider URLs updated
- [ ] Store metadata written
- [ ] Feature graphic (1024×500) created
- [ ] Content rating + data safety + app privacy completed
- [ ] Maestro verification passes on Android phone, iOS phone, iPad
- [ ] Manual WhatsApp test on real Android
- [ ] Build number auto-increment verified
- [ ] `functions-lint` CI disabled
