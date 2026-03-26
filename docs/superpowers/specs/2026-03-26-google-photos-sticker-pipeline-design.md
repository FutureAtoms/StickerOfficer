# Google Photos Smart Sticker Pipeline — Design Spec

**Date:** 2026-03-26
**Status:** Draft

---

## 1. Overview

Turn any Google Photos album into searchable, emotion-tagged sticker packs — automatically. Photos get AI background removal and sentiment tagging; videos get smart-split into animated stickers. Everything lives in the cloud (Cloudflare R2), downloads to device only when exporting to WhatsApp.

Two pipelines:
- **In-app pipeline** — regular users import albums of 200-800 photos, processed on-device via ONNX in the background
- **MacBook CLI pipeline** — developer batch tool for massive imports (13,000+ photos), runs locally with rembg + CLIP

---

## 2. User Stories

1. **As a user**, I tap "Sign in with Google" (one tap), and I'm logged in with my Google account.
2. **As a user**, I browse my Google Photos albums in the app, pick one, and tap "Import as Stickers."
3. **As a user**, I see a progress notification ("Processing your album... 127/500 stickers ready") while using the app normally.
4. **As a user**, I browse my cloud sticker library (thumbnails streamed from R2) without it eating device storage.
5. **As a user**, I download specific packs to my device and export to WhatsApp with emoji metadata for search.
6. **As a user**, I see a quick-export view listing all my albums with a WhatsApp icon on each — I tap multiple album icons to bulk-queue them for WhatsApp export.
7. **As a user**, I search for "angry" in WhatsApp and find stickers auto-tagged with the 😠 emoji.
8. **As a user**, I share private sticker packs with my girlfriend — she sees them in her account but they're not public.
9. **As a developer**, I run a CLI script on my MacBook to batch-process 13,000 photos overnight into sticker packs on R2.

---

## 3. Architecture

### 3.1 System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter App (Device)                     │
│                                                             │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │ Google    │  │ Album Browser│  │ Sticker Library       │ │
│  │ Sign-In   │→│ (Photos API) │→│ (R2 thumbnails)       │ │
│  └──────────┘  └──────────────┘  └───────────────────────┘ │
│                       │                      │              │
│                       ▼                      ▼              │
│  ┌───────────────────────────┐  ┌──────────────────────┐   │
│  │ Background Processing     │  │ WhatsApp Export       │   │
│  │ • ONNX bg removal         │  │ • On-demand download  │   │
│  │ • Emotion tagging (CLIP)  │  │ • Emoji metadata      │   │
│  │ • Video splitting (ffmpeg)│  │ • Quick-export view   │   │
│  └───────────────────────────┘  └──────────────────────┘   │
│                │                                            │
└────────────────│────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                  Cloudflare Infrastructure                    │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────────┐  │
│  │ Worker   │  │ D1       │  │ R2 Bucket               │  │
│  │ (API)    │  │ (SQLite) │  │ (sticker-officer-packs) │  │
│  │          │  │          │  │                          │  │
│  │ /auth    │  │ users    │  │ /{packId}/thumb_{n}.webp│  │
│  │ /google  │  │ packs    │  │ /{packId}/sticker_{n}   │  │
│  │ /packs   │  │ stickers │  │ /{packId}/manifest.json │  │
│  │ /share   │  │ shares   │  │                          │  │
│  │ /import  │  │ tags     │  │                          │  │
│  └──────────┘  └──────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              MacBook CLI (Developer Only)                     │
│                                                             │
│  google_photos_api → rembg → CLIP → ffmpeg → upload to R2  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Google Sign-In Flow

1. User taps "Sign in with Google" button
2. `google_sign_in` Flutter package handles native OAuth UI (one tap)
3. App requests scopes: `email`, `profile`, `https://www.googleapis.com/auth/photoslibrary.readonly`
4. App receives Google ID token + Photos API access token
5. App sends ID token to Cloudflare Worker `/auth/google`
6. Worker verifies token with Google, creates/finds user in D1
7. Worker returns app JWT (same format as existing device auth)
8. App stores JWT in `flutter_secure_storage`
9. Google Photos access token stored separately for Photos API calls

**Account linking:** If device already has device-auth, link Google account to existing device ID. User keeps all their existing local packs.

### 3.3 Google Photos Album Browser

**API:** Google Photos Library API v1

**Capabilities used:**
- `GET /v1/albums` — list user's albums (title, cover photo, item count)
- `POST /v1/mediaItems:search` — list items in an album (with pagination)
- `GET /v1/mediaItems/{id}` — get download URL for a single item

**API calls made directly from app** (not proxied through Worker) using the Google OAuth access token. The Worker is only involved for app auth and R2 storage — no need to relay Google Photos traffic through it.

**Limitations:**
- Face/person grouping is NOT available via API (Google restriction)
- Can only access albums, not "People" categories
- Access tokens expire after 1 hour — app refreshes via `google_sign_in` silently
- Media download URLs expire after 60 minutes — download promptly during processing

**UI:** Grid of album covers with title and photo count. Tap to preview contents. "Import as Stickers" button on each album.

### 3.4 Sticker Processing Pipeline (In-App)

Runs as a background isolate on-device when user imports a Google Photos album.

**For photos:**
1. Download photo from Google Photos API (temp file)
2. ONNX background removal (existing model in app) → transparent PNG
3. Resize/normalize to 512x512 WebP
4. Emotion classification via on-device MobileNet-based classifier (~10MB model, not CLIP which is too large for mobile) → 1-3 emojis
5. Upload processed sticker to R2 via Worker API
6. Delete temp files
7. Update progress notification

**For videos:**
1. Download video from Google Photos API (temp file)
2. Determine duration:
   - ≤ 8 seconds: one animated sticker (full video)
   - 8-16 seconds: two animated stickers (split at midpoint)
   - > 16 seconds: multiple stickers, each ~6-8 seconds, split evenly
3. Trim segments, normalize to WebP animated or GIF (≤500KB per sticker)
4. Upload to R2
5. Delete temp files

**Pack grouping:**
- Auto-split into packs of 30 stickers
- Pack naming: "{Album Name} (1/14)", "{Album Name} (2/14)", etc.
- First sticker of each pack becomes the tray icon
- All packs tagged with album name for grouping in UI

**Background processing UX:**
- Notification: "Importing {Album Name}... 127/500"
- User can use the app normally while processing
- Processing pauses if app is killed, resumes on next launch
- Progress persisted in local DB so it survives restarts

### 3.5 Sticker Metadata & Search

**Per-sticker metadata (stored in D1 + R2 manifest):**
```json
{
  "id": "sticker_uuid",
  "packId": "pack_uuid",
  "type": "static|animated",
  "emojis": ["😠", "💪"],
  "tags": ["angry", "strong", "gym"],
  "userText": "Don't mess with me",
  "sourceAlbum": "Bali Trip 2025",
  "createdAt": "2026-03-26T10:00:00Z"
}
```

**Emotion tagging pipeline:**
- On-device: lightweight MobileNet-based emotion classifier (~10MB, not CLIP which is ~400MB)
- Maps to emoji set: 😊😂😢😠😍🥰😎🤔😱🥳😴🤮 (12 base emotions)
- Multiple emotions possible per sticker (e.g., happy + love = 😊🥰)

**Text searchability:**
- User-added text stored in `userText` field
- In-app search queries `tags`, `emojis`, and `userText`
- WhatsApp export includes emoji associations in sticker pack format
- WhatsApp native search finds stickers by emoji match

### 3.6 Cloud-First Storage (Cloudflare R2)

**Storage layout on R2:**
```
sticker-officer-packs/
  {userId}/
    {packId}/
      manifest.json          # Pack metadata, sticker list, emojis
      tray_icon.webp         # 96x96 pack icon
      thumb_{n}.webp         # 128x128 thumbnails for browsing
      sticker_{n}.webp       # 512x512 full stickers
      sticker_{n}.webp.anim  # Animated stickers (if applicable)
```

**Storage estimates:**
- Thumbnail: ~5KB each
- Full sticker: ~75KB each (static), ~300KB (animated)
- 13,000 stickers: ~1GB full + ~65MB thumbnails
- Well within R2 free tier (10GB)

**Caching strategy:**
- Thumbnails: cached on device after first load (LRU cache, max 100MB)
- Full stickers: downloaded only when user taps "Download Pack" or exports to WhatsApp
- Manifests: cached 5 minutes, refreshed on pull-to-refresh

**Device storage impact:**
- Browsing: ~100MB cache (thumbnails only)
- Per downloaded pack: ~2.25MB (30 stickers × 75KB)
- WhatsApp export: WhatsApp makes its own copy (~2.25MB per pack)
- User controls what's on-device — cloud library takes zero permanent storage

### 3.7 Private Sharing

**Sharing model:**
- Pack owner can generate a share link or share directly with a user (by email/public ID)
- Shared packs appear in recipient's "Shared with Me" section
- Shared packs are NOT public — only visible to explicitly shared users
- Share permissions: `view` (can browse + export to WhatsApp) or `view+reshare`

**D1 schema addition:**
```sql
CREATE TABLE shares (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  shared_with_id TEXT,          -- NULL = share link (anyone with link)
  share_code TEXT UNIQUE,        -- For link-based sharing
  permission TEXT DEFAULT 'view', -- 'view' or 'view_reshare'
  created_at TEXT NOT NULL,
  FOREIGN KEY (pack_id) REFERENCES packs(id),
  FOREIGN KEY (owner_id) REFERENCES users(id)
);
```

**Share flow:**
1. Owner taps "Share" on a pack or album group
2. Options: "Copy Link" or "Share with..." (search by name/email)
3. Recipient opens link → app deep-links to shared pack
4. Recipient sees pack in "Shared with Me" tab
5. Recipient can download and export to WhatsApp like any other pack

### 3.8 Quick-Export WhatsApp View

**New screen:** "My Albums" view showing all imported album groups.

**Layout:**
- List/grid of album groups (each album may have multiple packs)
- Each row: album cover thumbnail, album name, pack count, total sticker count
- WhatsApp icon button on each row — tap to queue that album's packs for export
- Multi-select mode: tap multiple album icons, then "Export All" FAB
- Progress bar per album during export

**Export queue:**
1. User taps WhatsApp icons on albums
2. App queues selected packs for download (if not already on device)
3. Downloads from R2 in background
4. Exports each pack to WhatsApp via existing WhatsApp export service
5. Shows per-album status: queued → downloading → exporting → done

### 3.9 MacBook CLI Pipeline (Developer Tool)

**Tech stack:** Python 3.11+, standalone script

**Dependencies:**
- `google-auth-oauthlib` — Google Photos OAuth
- `google-api-python-client` — Photos Library API
- `rembg` — background removal (U2Net, local GPU via Metal)
- `open_clip` — emotion/sentiment classification (local)
- `ffmpeg-python` — video splitting
- `boto3` or `httpx` — R2 upload (S3-compatible API)

**CLI usage:**
```bash
# First run: authenticate with Google
python sticker_pipeline.py auth

# List albums
python sticker_pipeline.py albums

# Process a specific album
python sticker_pipeline.py process --album "Bali Trip 2025" --user-id <your_user_id>

# Process all albums for a person (manual album selection)
python sticker_pipeline.py process --albums "Album1,Album2,Album3" --user-id <your_user_id>

# Dry run (preview what would be created)
python sticker_pipeline.py process --album "Bali Trip 2025" --dry-run

# Process with sample first (test 10 photos before full run)
python sticker_pipeline.py process --album "Bali Trip 2025" --sample 10
```

**Processing steps per photo:**
1. Download from Google Photos API (respects rate limits, retries)
2. `rembg.remove()` — background removal with Metal GPU acceleration
3. Resize to 512x512, save as WebP
4. CLIP inference → emotion classification → emoji assignment
5. Generate 128x128 thumbnail
6. Upload sticker + thumbnail to R2
7. Log metadata to batch manifest

**Processing steps per video:**
1. Download from Google Photos API
2. `ffprobe` to get duration
3. Smart split based on duration rules (see 3.4)
4. `ffmpeg` trim + re-encode to WebP animated (≤500KB)
5. Upload to R2

**Batch completion:**
1. Group processed stickers into packs of 30
2. Generate pack manifests (JSON with metadata, emojis, tags)
3. Upload manifests to R2
4. Register all packs in D1 via Worker API (`POST /packs/register-batch`)
5. Print summary: X packs created, Y stickers, Z errors

**Performance estimate (M-series MacBook):**
- rembg: ~1-2 sec/photo
- CLIP emotion: ~0.5 sec/photo
- Upload: ~0.2 sec/photo
- Total: ~2-3 sec/photo
- 13,000 photos: ~8-10 hours (overnight run)
- 800-photo album: ~30-40 minutes

**Sample/test mode:**
- `--sample 10` processes first 10 photos and shows results
- User reviews quality before committing to full album
- Can adjust parameters (model, threshold) based on sample

---

## 4. Data Model Changes

### 4.1 D1 Schema Additions

```sql
-- Users table (extends existing device auth)
ALTER TABLE users ADD COLUMN google_id TEXT;
ALTER TABLE users ADD COLUMN google_email TEXT;
ALTER TABLE users ADD COLUMN google_name TEXT;
ALTER TABLE users ADD COLUMN google_photo TEXT;

-- Sticker metadata (new table)
CREATE TABLE sticker_metadata (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL,
  sticker_index INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'static',  -- 'static' or 'animated'
  emojis TEXT,                           -- JSON array of emoji strings
  tags TEXT,                             -- JSON array of tag strings
  user_text TEXT,                        -- User-added text on sticker
  source_album TEXT,                     -- Google Photos album name
  r2_key TEXT NOT NULL,                  -- R2 object key
  thumb_r2_key TEXT,                     -- Thumbnail R2 key
  created_at TEXT NOT NULL,
  FOREIGN KEY (pack_id) REFERENCES packs(id)
);

-- Import jobs (track background processing)
CREATE TABLE import_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  album_id TEXT,
  album_name TEXT,
  total_items INTEGER NOT NULL,
  processed_items INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending',         -- pending, processing, completed, failed, paused
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Shares table (see 3.7)
CREATE TABLE shares (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  shared_with_id TEXT,
  share_code TEXT UNIQUE,
  permission TEXT DEFAULT 'view',
  created_at TEXT NOT NULL,
  FOREIGN KEY (pack_id) REFERENCES packs(id),
  FOREIGN KEY (owner_id) REFERENCES users(id)
);
```

### 4.2 StickerPack Model Extension

```dart
class StickerPack {
  // ... existing fields ...

  // New fields
  final String? sourceAlbum;      // Google Photos album origin
  final String? albumGroupId;     // Groups packs from same album
  final String? ownerId;          // User who created the pack
  final bool isCloudOnly;         // True = not downloaded to device
  final String? r2Prefix;         // R2 path prefix for this pack
  final List<StickerMeta>? stickerMeta; // Per-sticker metadata
}

class StickerMeta {
  final String id;
  final List<String> emojis;      // ["😠", "💪"]
  final List<String> tags;        // ["angry", "strong"]
  final String? userText;         // Text overlay content
  final String r2Key;             // Full R2 object key
  final String? thumbR2Key;       // Thumbnail key
}
```

---

## 5. New Worker API Endpoints

```
POST   /auth/google              — Exchange Google ID token for app JWT
                                   (Google Photos API called directly from app, not proxied)

POST   /import/start             — Start an import job
PUT    /import/:jobId/progress   — Update import progress
GET    /import/:jobId            — Get import job status
POST   /import/:jobId/complete   — Finalize import, register packs

POST   /packs/register-batch     — Register multiple packs at once (CLI use)
GET    /packs/:id/manifest       — Get pack manifest with sticker metadata
GET    /packs/cloud              — List user's cloud-only packs (not downloaded)
POST   /packs/:id/download-urls  — Get signed download URLs for pack stickers

POST   /share                    — Create a share (link or direct)
GET    /shared-with-me           — List packs shared with current user
GET    /share/:code              — Resolve share link to pack
DELETE /share/:id                — Revoke a share
```

---

## 6. New App Screens & Navigation

1. **Google Sign-In Button** — on profile screen (or onboarding)
2. **Album Browser Screen** — grid of Google Photos albums after sign-in
3. **Album Preview Screen** — preview photos in album before importing
4. **Import Progress Screen** — shows active/completed import jobs
5. **Cloud Library Screen** — browse all cloud sticker packs (thumbnails from R2)
6. **Quick-Export View** — album list with WhatsApp tap-to-queue icons
7. **Share Sheet** — share pack via link or search for user
8. **Shared With Me Tab** — view packs others have shared with you

**Navigation additions to GoRouter:**
```
/google-albums          → Album Browser
/google-albums/:id      → Album Preview
/import-progress        → Import Jobs
/cloud-library          → Cloud Sticker Library
/quick-export           → Quick WhatsApp Export
/shared                 → Shared With Me
```

---

## 7. WhatsApp Export Enhancement

**Current:** Export packs from local storage with basic metadata.

**Enhanced:**
- Include emoji associations per sticker in WAStickers format
- Emoji field populated from AI emotion tagging
- User-added text stored but not directly searchable in WhatsApp (WhatsApp only searches emojis)
- In-app search covers emojis + tags + userText for finding the right sticker before export

**WAStickers emoji format:**
```json
{
  "sticker_packs": [{
    "name": "Bali Trip 2025 (1/14)",
    "stickers": [
      {
        "image_file": "sticker_1.webp",
        "emojis": ["😊", "🌴", "🥰"]
      }
    ]
  }]
}
```

---

## 8. Scope & Phasing

### Phase 1: Foundation (build first)
- Google Sign-In (one-tap, account linking with device auth)
- Worker `/auth/google` endpoint
- D1 schema additions (users, shares, sticker_metadata, import_jobs)
- Cloud pack model (R2 storage, manifests, thumbnails)

### Phase 2: Google Photos Import (in-app)
- Album browser screen
- Album preview screen
- Background processing pipeline (ONNX bg removal + emotion tagging)
- Import progress tracking with notifications
- Auto-grouping into packs of 30

### Phase 3: Cloud Library & WhatsApp Export
- Cloud library browsing (thumbnails from R2)
- On-demand pack download
- Enhanced WhatsApp export with emoji metadata
- Quick-export view with tap-to-queue

### Phase 4: Private Sharing
- Share via link or direct user search
- Shared With Me tab
- Share permissions (view / view+reshare)

### Phase 5: MacBook CLI Pipeline
- Python script with Google Photos OAuth
- rembg + CLIP + ffmpeg local processing
- Batch upload to R2 + D1 registration
- Sample/test mode for quality verification

---

## 9. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Google Photos API rate limits | Slow imports for large albums | Batch requests, respect quotas, exponential backoff |
| ONNX bg removal quality varies | Some stickers look bad | Keep original as fallback, let user toggle bg removal per pack |
| Google Photos API deprecation | Feature breaks | Abstract behind service interface, Google Takeout as fallback |
| R2 free tier exceeded | Storage costs | Monitor usage, compress aggressively, alert at 8GB |
| Large album processing killed by OS | Lost progress | Persist progress per-sticker, resume from last completed |
| WhatsApp sticker pack limit | Can't add 400+ packs | WhatsApp has no hard limit on installed packs, but UX degrades — quick-export helps manage |

---

## 10. Out of Scope

- Face/person grouping from Google Photos API (not available)
- Server-side ML processing (using on-device ONNX instead)
- Real-time collaborative editing of stickers
- AI style transfer during import (can be added later)
- Cross-platform MacBook CLI (macOS only for now)
- Sticker text OCR for searchability (manual text only)
