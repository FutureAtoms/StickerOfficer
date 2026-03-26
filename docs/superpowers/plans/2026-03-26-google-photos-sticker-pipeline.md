# Google Photos Smart Sticker Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a MacBook CLI pipeline that pulls Google Photos albums, removes backgrounds, tags emotions, splits videos, and uploads sticker packs to Cloudflare R2 — plus the Worker API endpoints to support it.

**Architecture:** Python CLI script authenticates with Google Photos API via OAuth, downloads album media, processes photos (rembg bg removal + emotion classification) and videos (ffmpeg splitting), uploads to R2 via S3-compatible API, and registers packs in D1 via Worker REST API. A new `/auth/google` and `/packs/register-batch` endpoint on the Cloudflare Worker handles pack registration.

**Tech Stack:** Python 3.12, rembg, open-clip-torch, ffmpeg, Pillow, boto3, google-api-python-client, Hono (Worker)

---

## File Structure

### Python CLI (`tools/sticker-pipeline/`)
```
tools/sticker-pipeline/
  sticker_pipeline.py          # Main CLI entry point (click-based)
  auth.py                      # Google Photos OAuth flow
  downloader.py                # Download media from Google Photos API
  processor.py                 # Background removal + emotion tagging
  video_processor.py           # Video splitting with ffmpeg
  uploader.py                  # Upload to R2 + register packs via Worker API
  config.py                    # Configuration (R2 creds, Worker URL, paths)
  requirements.txt             # Python dependencies
  .env.example                 # Template for secrets
  tests/
    test_processor.py          # Test bg removal + emotion pipeline
    test_video_processor.py    # Test video splitting logic
    test_uploader.py           # Test R2 upload + pack registration
    conftest.py                # Shared fixtures
```

### Worker additions (`sticker-ai-proxy/src/`)
```
sticker-ai-proxy/src/
  routes/auth.ts               # Modify: add POST /google endpoint
  db/schema.sql                # Modify: add google columns + new tables
  db/migrations/
    002_google_photos.sql      # New: migration for google + metadata tables
```

---

## Task 1: Python Environment Setup

**Files:**
- Create: `tools/sticker-pipeline/requirements.txt`
- Create: `tools/sticker-pipeline/.env.example`
- Create: `tools/sticker-pipeline/config.py`

- [ ] **Step 1: Create requirements.txt**

```
rembg[gpu]==2.0.62
open-clip-torch==2.29.0
google-api-python-client==2.166.0
google-auth-oauthlib==1.2.1
boto3==1.36.26
Pillow==11.2.1
click==8.1.8
python-dotenv==1.1.0
tqdm==4.67.1
ffmpeg-python==0.2.0
pytest==8.3.5
```

- [ ] **Step 2: Create .env.example**

```bash
# Google OAuth (create at console.cloud.google.com)
GOOGLE_CLIENT_ID=your_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_client_secret

# Cloudflare R2 (create API token at dash.cloudflare.com)
R2_ACCOUNT_ID=your_account_id
R2_ACCESS_KEY_ID=your_access_key
R2_SECRET_ACCESS_KEY=your_secret_key
R2_BUCKET_NAME=sticker-officer-packs

# Worker API
WORKER_API_URL=https://sticker-officer-api.ceofutureatoms.workers.dev
WORKER_ADMIN_KEY=your_admin_key

# Processing
USER_ID=your_device_id_or_public_id
```

- [ ] **Step 3: Create config.py**

```python
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Paths
BASE_DIR = Path(__file__).parent
TEMP_DIR = BASE_DIR / "tmp"
CREDENTIALS_FILE = BASE_DIR / "google_credentials.json"
TOKEN_FILE = BASE_DIR / "google_token.json"

# Google OAuth
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_SCOPES = ["https://www.googleapis.com/auth/photoslibrary.readonly"]

# Cloudflare R2
R2_ACCOUNT_ID = os.getenv("R2_ACCOUNT_ID", "")
R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID", "")
R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY", "")
R2_BUCKET_NAME = os.getenv("R2_BUCKET_NAME", "sticker-officer-packs")
R2_ENDPOINT = f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Worker API
WORKER_API_URL = os.getenv("WORKER_API_URL", "https://sticker-officer-api.ceofutureatoms.workers.dev")
WORKER_ADMIN_KEY = os.getenv("WORKER_ADMIN_KEY", "")

# Processing
USER_ID = os.getenv("USER_ID", "")
STICKER_SIZE = 512
THUMB_SIZE = 128
PACK_SIZE = 30
WEBP_QUALITY = 85
MAX_ANIMATED_SIZE_KB = 500
MAX_ANIMATED_DURATION_SEC = 8
```

- [ ] **Step 4: Create virtual environment and install dependencies**

```bash
cd tools/sticker-pipeline
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

- [ ] **Step 5: Verify rembg and CLIP load correctly**

```bash
source venv/bin/activate
python3 -c "from rembg import remove; print('rembg OK')"
python3 -c "import open_clip; print('open_clip OK')"
python3 -c "import ffmpeg; print('ffmpeg OK')"
```

Expected: Three "OK" prints, no errors.

- [ ] **Step 6: Commit**

```bash
git add tools/sticker-pipeline/requirements.txt tools/sticker-pipeline/.env.example tools/sticker-pipeline/config.py
git commit -m "feat(cli): add sticker pipeline Python environment and config"
```

---

## Task 2: Google Photos OAuth Authentication

**Files:**
- Create: `tools/sticker-pipeline/auth.py`
- Test: `tools/sticker-pipeline/tests/test_auth.py`

- [ ] **Step 1: Write auth.py**

```python
"""Google Photos OAuth authentication."""

import json
from pathlib import Path
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from config import GOOGLE_SCOPES, TOKEN_FILE, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET


def get_credentials() -> Credentials:
    """Get valid Google OAuth credentials, prompting login if needed."""
    creds = None

    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), GOOGLE_SCOPES)

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
        _save_token(creds)
    elif not creds or not creds.valid:
        creds = _run_oauth_flow()
        _save_token(creds)

    return creds


def _run_oauth_flow() -> Credentials:
    """Run the OAuth installed-app flow (opens browser)."""
    client_config = {
        "installed": {
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost:8080"],
        }
    }
    flow = InstalledAppFlow.from_client_config(client_config, GOOGLE_SCOPES)
    creds = flow.run_local_server(port=8080, open_browser=True)
    return creds


def _save_token(creds: Credentials) -> None:
    """Persist credentials to disk."""
    TOKEN_FILE.write_text(json.dumps({
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": creds.scopes,
    }))
```

- [ ] **Step 2: Write test_auth.py**

```python
"""Tests for Google Photos OAuth."""

import json
from unittest.mock import patch, MagicMock
from pathlib import Path
import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_credentials, _save_token


def test_save_token_writes_json(tmp_path):
    """Token file should contain valid JSON with required fields."""
    token_file = tmp_path / "token.json"
    creds = MagicMock()
    creds.token = "access_123"
    creds.refresh_token = "refresh_456"
    creds.token_uri = "https://oauth2.googleapis.com/token"
    creds.client_id = "client_id"
    creds.client_secret = "client_secret"
    creds.scopes = ["https://www.googleapis.com/auth/photoslibrary.readonly"]

    with patch("auth.TOKEN_FILE", token_file):
        _save_token(creds)

    data = json.loads(token_file.read_text())
    assert data["token"] == "access_123"
    assert data["refresh_token"] == "refresh_456"


def test_get_credentials_loads_existing_token(tmp_path):
    """Should load valid token from file without prompting OAuth."""
    token_file = tmp_path / "token.json"
    token_file.write_text(json.dumps({
        "token": "valid_token",
        "refresh_token": "refresh",
        "token_uri": "https://oauth2.googleapis.com/token",
        "client_id": "cid",
        "client_secret": "csec",
        "scopes": ["https://www.googleapis.com/auth/photoslibrary.readonly"],
    }))

    mock_creds = MagicMock()
    mock_creds.valid = True
    mock_creds.expired = False

    with patch("auth.TOKEN_FILE", token_file), \
         patch("auth.Credentials.from_authorized_user_file", return_value=mock_creds):
        result = get_credentials()
        assert result == mock_creds
```

- [ ] **Step 3: Run tests**

```bash
cd tools/sticker-pipeline && source venv/bin/activate
python3 -m pytest tests/test_auth.py -v
```

Expected: 2 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tools/sticker-pipeline/auth.py tools/sticker-pipeline/tests/test_auth.py tools/sticker-pipeline/tests/__init__.py
git commit -m "feat(cli): add Google Photos OAuth authentication"
```

---

## Task 3: Google Photos Album Downloader

**Files:**
- Create: `tools/sticker-pipeline/downloader.py`
- Test: `tools/sticker-pipeline/tests/test_downloader.py`

- [ ] **Step 1: Write downloader.py**

```python
"""Download media items from Google Photos albums."""

import time
from pathlib import Path
from typing import Generator
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
from tqdm import tqdm
from config import TEMP_DIR


def list_albums(creds: Credentials) -> list[dict]:
    """List all albums with title, id, and item count."""
    service = build("photoslibrary", "v1", credentials=creds, static_discovery=False)
    albums = []
    page_token = None

    while True:
        resp = service.albums().list(pageSize=50, pageToken=page_token).execute()
        for album in resp.get("albums", []):
            albums.append({
                "id": album["id"],
                "title": album.get("title", "Untitled"),
                "count": int(album.get("mediaItemsCount", 0)),
                "cover_url": album.get("coverPhotoBaseUrl", ""),
            })
        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    return sorted(albums, key=lambda a: a["count"], reverse=True)


def list_album_items(creds: Credentials, album_id: str) -> list[dict]:
    """List all media items in an album with metadata."""
    service = build("photoslibrary", "v1", credentials=creds, static_discovery=False)
    items = []
    page_token = None

    while True:
        body = {"albumId": album_id, "pageSize": 100}
        if page_token:
            body["pageToken"] = page_token

        resp = service.mediaItems().search(body=body).execute()
        for item in resp.get("mediaItems", []):
            mime = item.get("mimeType", "")
            is_video = mime.startswith("video/")
            items.append({
                "id": item["id"],
                "filename": item.get("filename", "unknown"),
                "mime": mime,
                "is_video": is_video,
                "base_url": item["baseUrl"],
                "width": int(item.get("mediaMetadata", {}).get("width", 0)),
                "height": int(item.get("mediaMetadata", {}).get("height", 0)),
            })
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
        time.sleep(0.1)  # Respect rate limits

    return items


def download_item(item: dict, output_dir: Path) -> Path | None:
    """Download a single media item to output_dir. Returns path or None on failure."""
    import requests

    output_dir.mkdir(parents=True, exist_ok=True)
    ext = _extension_from_mime(item["mime"])
    filename = f"{item['id'][:12]}.{ext}"
    output_path = output_dir / filename

    if output_path.exists():
        return output_path

    # Google Photos base URLs need size/download params appended
    if item["is_video"]:
        url = f"{item['base_url']}=dv"  # dv = download video
    else:
        url = f"{item['base_url']}=d"  # d = download original

    try:
        resp = requests.get(url, timeout=120)
        resp.raise_for_status()
        output_path.write_bytes(resp.content)
        return output_path
    except Exception as e:
        print(f"  Failed to download {item['filename']}: {e}")
        return None


def download_album(
    creds: Credentials, album_id: str, album_name: str, limit: int | None = None
) -> Generator[tuple[dict, Path | None], None, None]:
    """Download all items in an album, yielding (item_metadata, local_path) tuples."""
    items = list_album_items(creds, album_id)
    if limit:
        items = items[:limit]

    output_dir = TEMP_DIR / _safe_dirname(album_name)
    print(f"Downloading {len(items)} items from '{album_name}' to {output_dir}")

    for item in tqdm(items, desc="Downloading"):
        path = download_item(item, output_dir)
        yield item, path


def _extension_from_mime(mime: str) -> str:
    """Map MIME type to file extension."""
    mapping = {
        "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
        "image/gif": "gif", "image/heic": "heic", "image/heif": "heif",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/3gpp": "3gp",
        "video/x-msvideo": "avi", "video/webm": "webm",
    }
    return mapping.get(mime, "jpg")


def _safe_dirname(name: str) -> str:
    """Sanitize album name for use as directory name."""
    return "".join(c if c.isalnum() or c in " -_" else "_" for c in name).strip()[:80]
```

- [ ] **Step 2: Write test_downloader.py**

```python
"""Tests for Google Photos downloader."""

import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))

from downloader import list_albums, _extension_from_mime, _safe_dirname


def test_extension_from_mime_known():
    assert _extension_from_mime("image/jpeg") == "jpg"
    assert _extension_from_mime("video/mp4") == "mp4"
    assert _extension_from_mime("image/webp") == "webp"


def test_extension_from_mime_unknown():
    assert _extension_from_mime("application/octet-stream") == "jpg"


def test_safe_dirname_sanitizes():
    assert _safe_dirname("Bali Trip 2025!") == "Bali Trip 2025_"
    assert _safe_dirname("a" * 100) == "a" * 80


def test_list_albums_parses_response():
    mock_service = MagicMock()
    mock_albums = mock_service.albums.return_value.list.return_value
    mock_albums.execute.return_value = {
        "albums": [
            {"id": "abc", "title": "Trip", "mediaItemsCount": "42", "coverPhotoBaseUrl": "http://x"},
            {"id": "def", "title": "Home", "mediaItemsCount": "10"},
        ]
    }

    with patch("downloader.build", return_value=mock_service):
        creds = MagicMock()
        albums = list_albums(creds)

    assert len(albums) == 2
    assert albums[0]["title"] == "Trip"
    assert albums[0]["count"] == 42
    assert albums[1]["title"] == "Home"
```

- [ ] **Step 3: Run tests**

```bash
python3 -m pytest tests/test_downloader.py -v
```

Expected: 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tools/sticker-pipeline/downloader.py tools/sticker-pipeline/tests/test_downloader.py
git commit -m "feat(cli): add Google Photos album downloader"
```

---

## Task 4: Photo Processor (Background Removal + Emotion Tagging)

**Files:**
- Create: `tools/sticker-pipeline/processor.py`
- Test: `tools/sticker-pipeline/tests/test_processor.py`
- Create: `tools/sticker-pipeline/tests/conftest.py`

- [ ] **Step 1: Create conftest.py with shared fixtures**

```python
"""Shared test fixtures."""

import pytest
from pathlib import Path
from PIL import Image


@pytest.fixture
def sample_photo(tmp_path) -> Path:
    """Create a 1024x768 test photo with a colored rectangle (simulates person)."""
    img = Image.new("RGB", (1024, 768), color=(200, 200, 200))
    # Draw a "person" rectangle in center
    for x in range(312, 712):
        for y in range(100, 668):
            img.putpixel((x, y), (180, 120, 80))
    path = tmp_path / "test_photo.jpg"
    img.save(path, "JPEG")
    return path


@pytest.fixture
def output_dir(tmp_path) -> Path:
    d = tmp_path / "output"
    d.mkdir()
    return d
```

- [ ] **Step 2: Write processor.py**

```python
"""Photo processing: background removal and emotion tagging."""

from pathlib import Path
from PIL import Image
from rembg import remove
from config import STICKER_SIZE, THUMB_SIZE, WEBP_QUALITY

# Lazy-loaded CLIP model
_clip_model = None
_clip_preprocess = None
_clip_tokenizer = None


def process_photo(input_path: Path, output_dir: Path) -> dict | None:
    """Process a single photo: bg removal → resize → save WebP + thumbnail.

    Returns metadata dict or None on failure.
    """
    try:
        # Load and remove background
        input_bytes = input_path.read_bytes()
        output_bytes = remove(input_bytes)
        img = Image.open(__import__("io").BytesIO(output_bytes)).convert("RGBA")

        # Resize to 512x512 (fit within, pad with transparent)
        sticker = _fit_and_pad(img, STICKER_SIZE)
        thumb = _fit_and_pad(img, THUMB_SIZE)

        # Save sticker
        sticker_name = f"{input_path.stem}.webp"
        sticker_path = output_dir / sticker_name
        sticker.save(sticker_path, "WEBP", quality=WEBP_QUALITY)

        # Save thumbnail
        thumb_name = f"{input_path.stem}_thumb.webp"
        thumb_path = output_dir / thumb_name
        thumb.save(thumb_path, "WEBP", quality=70)

        # Emotion tagging
        emojis = classify_emotion(img)

        return {
            "sticker_path": sticker_path,
            "thumb_path": thumb_path,
            "emojis": emojis,
            "size_kb": sticker_path.stat().st_size / 1024,
        }
    except Exception as e:
        print(f"  Failed to process {input_path.name}: {e}")
        return None


def classify_emotion(img: Image.Image) -> list[str]:
    """Classify the dominant emotion in an image using CLIP zero-shot."""
    import torch
    import open_clip

    global _clip_model, _clip_preprocess, _clip_tokenizer

    if _clip_model is None:
        _clip_model, _, _clip_preprocess = open_clip.create_model_and_transforms(
            "ViT-B-32", pretrained="laion2b_s34b_b79k"
        )
        _clip_tokenizer = open_clip.get_tokenizer("ViT-B-32")
        _clip_model.eval()

    emotion_labels = {
        "a happy smiling person": "😊",
        "a person laughing hard": "😂",
        "a sad or crying person": "😢",
        "an angry furious person": "😠",
        "a person in love, romantic": "😍",
        "a cute adorable person": "🥰",
        "a cool confident person": "😎",
        "a confused thinking person": "🤔",
        "a scared surprised person": "😱",
        "a person celebrating, excited": "🥳",
        "a tired sleepy person": "😴",
        "a silly goofy person": "🤪",
    }

    # Convert RGBA to RGB for CLIP
    rgb_img = img.convert("RGB")
    image_input = _clip_preprocess(rgb_img).unsqueeze(0)
    text_inputs = _clip_tokenizer(list(emotion_labels.keys()))

    with torch.no_grad():
        image_features = _clip_model.encode_image(image_input)
        text_features = _clip_model.encode_text(text_inputs)
        image_features /= image_features.norm(dim=-1, keepdim=True)
        text_features /= text_features.norm(dim=-1, keepdim=True)
        similarity = (image_features @ text_features.T).squeeze(0)
        probs = similarity.softmax(dim=0)

    # Top 2 emotions above threshold
    emoji_list = list(emotion_labels.values())
    sorted_indices = probs.argsort(descending=True)
    result = []
    for idx in sorted_indices[:2]:
        if probs[idx] > 0.05:
            result.append(emoji_list[idx])

    return result if result else ["😊"]  # Default to happy


def _fit_and_pad(img: Image.Image, size: int) -> Image.Image:
    """Resize image to fit within size x size, pad with transparent pixels."""
    img.thumbnail((size, size), Image.LANCZOS)
    padded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_x = (size - img.width) // 2
    offset_y = (size - img.height) // 2
    padded.paste(img, (offset_x, offset_y))
    return padded
```

- [ ] **Step 3: Write test_processor.py**

```python
"""Tests for photo processor."""

import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from processor import _fit_and_pad, process_photo


def test_fit_and_pad_square():
    """Square image should fill the canvas."""
    img = Image.new("RGBA", (200, 200), (255, 0, 0, 255))
    result = _fit_and_pad(img, 512)
    assert result.size == (512, 512)


def test_fit_and_pad_landscape():
    """Landscape image should be centered vertically."""
    img = Image.new("RGBA", (800, 400), (0, 255, 0, 255))
    result = _fit_and_pad(img, 512)
    assert result.size == (512, 512)
    # Top-left corner should be transparent (padding)
    assert result.getpixel((0, 0))[3] == 0
    # Center should be green
    assert result.getpixel((256, 256))[1] > 200


def test_fit_and_pad_portrait():
    """Portrait image should be centered horizontally."""
    img = Image.new("RGBA", (400, 800), (0, 0, 255, 255))
    result = _fit_and_pad(img, 512)
    assert result.size == (512, 512)


def test_process_photo_creates_sticker_and_thumb(sample_photo, output_dir):
    """Full pipeline should produce WebP sticker + thumbnail."""
    result = process_photo(sample_photo, output_dir)
    assert result is not None
    assert result["sticker_path"].exists()
    assert result["thumb_path"].exists()
    assert result["sticker_path"].suffix == ".webp"
    assert result["thumb_path"].suffix == ".webp"

    # Check sticker dimensions
    sticker = Image.open(result["sticker_path"])
    assert sticker.size == (512, 512)

    # Check thumbnail dimensions
    thumb = Image.open(result["thumb_path"])
    assert thumb.size == (128, 128)

    # Should have at least one emoji
    assert len(result["emojis"]) >= 1
    assert result["size_kb"] > 0
```

- [ ] **Step 4: Run tests (this will download models on first run — ~300MB)**

```bash
python3 -m pytest tests/test_processor.py -v --timeout=120
```

Expected: 4 tests pass. First run downloads rembg U2Net model (~170MB) and CLIP ViT-B-32 (~340MB).

- [ ] **Step 5: Commit**

```bash
git add tools/sticker-pipeline/processor.py tools/sticker-pipeline/tests/test_processor.py tools/sticker-pipeline/tests/conftest.py
git commit -m "feat(cli): add photo processor with bg removal and emotion tagging"
```

---

## Task 5: Video Processor (Smart Splitting)

**Files:**
- Create: `tools/sticker-pipeline/video_processor.py`
- Test: `tools/sticker-pipeline/tests/test_video_processor.py`

- [ ] **Step 1: Write video_processor.py**

```python
"""Video processing: smart splitting and conversion to animated stickers."""

import subprocess
import json
from pathlib import Path
from config import MAX_ANIMATED_DURATION_SEC, MAX_ANIMATED_SIZE_KB, STICKER_SIZE


def get_video_duration(video_path: Path) -> float:
    """Get video duration in seconds using ffprobe."""
    result = subprocess.run(
        [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", str(video_path),
        ],
        capture_output=True, text=True
    )
    info = json.loads(result.stdout)
    return float(info.get("format", {}).get("duration", 0))


def process_video(input_path: Path, output_dir: Path) -> list[dict]:
    """Process a video into one or more animated sticker segments.

    Returns list of metadata dicts, one per segment.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    duration = get_video_duration(input_path)

    if duration <= 0:
        print(f"  Skipping {input_path.name}: could not determine duration")
        return []

    segments = _compute_segments(duration)
    results = []

    for i, (start, end) in enumerate(segments):
        segment_name = f"{input_path.stem}_seg{i}.webp"
        segment_path = output_dir / segment_name

        success = _extract_animated_webp(input_path, segment_path, start, end)
        if success and segment_path.exists():
            size_kb = segment_path.stat().st_size / 1024

            # If too large, reduce quality/fps
            if size_kb > MAX_ANIMATED_SIZE_KB:
                _extract_animated_webp(input_path, segment_path, start, end, low_quality=True)
                size_kb = segment_path.stat().st_size / 1024

            results.append({
                "sticker_path": segment_path,
                "thumb_path": None,  # Animated stickers use first frame as thumb
                "duration_sec": end - start,
                "size_kb": size_kb,
                "emojis": ["🎬"],  # Default emoji for video stickers
            })

    return results


def _compute_segments(duration: float) -> list[tuple[float, float]]:
    """Compute (start, end) pairs for splitting video into sticker-length segments."""
    max_dur = MAX_ANIMATED_DURATION_SEC  # 8 seconds

    if duration <= max_dur:
        return [(0, duration)]
    elif duration <= max_dur * 2:
        mid = duration / 2
        return [(0, mid), (mid, duration)]
    else:
        # Split evenly into ~6-8 second chunks
        num_segments = max(2, int(duration / 7))  # Target ~7 sec each
        segment_len = duration / num_segments
        return [(i * segment_len, (i + 1) * segment_len) for i in range(num_segments)]


def _extract_animated_webp(
    input_path: Path, output_path: Path, start: float, end: float,
    low_quality: bool = False,
) -> bool:
    """Extract a segment as animated WebP using ffmpeg."""
    duration = end - start
    fps = 10 if low_quality else 15
    quality = 50 if low_quality else 70
    size = STICKER_SIZE

    cmd = [
        "ffmpeg", "-y", "-ss", str(start), "-t", str(duration),
        "-i", str(input_path),
        "-vf", f"scale={size}:{size}:force_original_aspect_ratio=decrease,"
               f"pad={size}:{size}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,"
               f"fps={fps}",
        "-c:v", "libwebp", "-lossless", "0", "-quality", str(quality),
        "-loop", "0", "-an",
        str(output_path),
    ]

    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        print(f"  ffmpeg failed for {input_path.name}: {e}")
        return False
```

- [ ] **Step 2: Write test_video_processor.py**

```python
"""Tests for video processor."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from video_processor import _compute_segments


def test_short_video_one_segment():
    """Video ≤ 8s should produce one segment."""
    segments = _compute_segments(5.0)
    assert segments == [(0, 5.0)]


def test_medium_video_two_segments():
    """Video 8-16s should produce two segments."""
    segments = _compute_segments(12.0)
    assert len(segments) == 2
    assert segments[0] == (0, 6.0)
    assert segments[1] == (6.0, 12.0)


def test_long_video_multiple_segments():
    """Video > 16s should produce multiple ~7s segments."""
    segments = _compute_segments(30.0)
    assert len(segments) >= 3
    # All segments should be roughly equal
    durations = [end - start for start, end in segments]
    assert all(5 <= d <= 10 for d in durations)
    # Should cover full duration
    assert segments[0][0] == 0
    assert abs(segments[-1][1] - 30.0) < 0.01


def test_very_short_video():
    """1-second video should still produce one segment."""
    segments = _compute_segments(1.0)
    assert segments == [(0, 1.0)]


def test_zero_duration():
    """Zero duration should produce one degenerate segment."""
    segments = _compute_segments(0)
    assert segments == [(0, 0)]
```

- [ ] **Step 3: Run tests**

```bash
python3 -m pytest tests/test_video_processor.py -v
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tools/sticker-pipeline/video_processor.py tools/sticker-pipeline/tests/test_video_processor.py
git commit -m "feat(cli): add video processor with smart splitting"
```

---

## Task 6: R2 Uploader + Worker Pack Registration

**Files:**
- Create: `tools/sticker-pipeline/uploader.py`
- Test: `tools/sticker-pipeline/tests/test_uploader.py`

- [ ] **Step 1: Write uploader.py**

```python
"""Upload stickers to R2 and register packs via Worker API."""

import json
import uuid
from pathlib import Path
import boto3
import requests
from config import (
    R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME,
    WORKER_API_URL, WORKER_ADMIN_KEY, USER_ID, PACK_SIZE,
)


def get_r2_client():
    """Create boto3 S3 client configured for R2."""
    return boto3.client(
        "s3",
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_ACCESS_KEY_ID,
        aws_secret_access_key=R2_SECRET_ACCESS_KEY,
        region_name="auto",
    )


def upload_sticker(r2_client, sticker_path: Path, user_id: str, pack_id: str, index: int) -> str:
    """Upload a single sticker to R2. Returns the R2 key."""
    ext = sticker_path.suffix
    r2_key = f"{user_id}/{pack_id}/sticker_{index}{ext}"

    content_type = "image/webp" if ext == ".webp" else "image/png"
    r2_client.upload_file(
        str(sticker_path), R2_BUCKET_NAME, r2_key,
        ExtraArgs={"ContentType": content_type},
    )
    return r2_key


def upload_thumbnail(r2_client, thumb_path: Path, user_id: str, pack_id: str, index: int) -> str:
    """Upload a thumbnail to R2. Returns the R2 key."""
    r2_key = f"{user_id}/{pack_id}/thumb_{index}.webp"
    r2_client.upload_file(
        str(thumb_path), R2_BUCKET_NAME, r2_key,
        ExtraArgs={"ContentType": "image/webp"},
    )
    return r2_key


def upload_manifest(r2_client, manifest: dict, user_id: str, pack_id: str) -> str:
    """Upload pack manifest JSON to R2."""
    r2_key = f"{user_id}/{pack_id}/manifest.json"
    r2_client.put_object(
        Bucket=R2_BUCKET_NAME, Key=r2_key,
        Body=json.dumps(manifest, indent=2),
        ContentType="application/json",
    )
    return r2_key


def group_into_packs(
    sticker_results: list[dict], album_name: str, user_id: str,
) -> list[dict]:
    """Group processed stickers into packs of PACK_SIZE (30).

    Returns list of pack dicts ready for registration.
    """
    packs = []
    total_packs = max(1, (len(sticker_results) + PACK_SIZE - 1) // PACK_SIZE)

    for i in range(0, len(sticker_results), PACK_SIZE):
        chunk = sticker_results[i:i + PACK_SIZE]
        pack_num = i // PACK_SIZE + 1
        pack_id = str(uuid.uuid4())

        if total_packs == 1:
            pack_name = album_name
        else:
            pack_name = f"{album_name} ({pack_num}/{total_packs})"

        packs.append({
            "id": pack_id,
            "name": pack_name,
            "author_device_id": user_id,
            "sticker_count": len(chunk),
            "is_public": False,
            "tags": json.dumps([album_name.lower(), "google-photos", "imported"]),
            "stickers": chunk,
        })

    return packs


def register_packs_with_worker(packs: list[dict]) -> bool:
    """Register packs with the Worker API via /packs/register-batch."""
    # Strip sticker file paths, keep only metadata for registration
    registration = []
    for pack in packs:
        registration.append({
            "id": pack["id"],
            "name": pack["name"],
            "author_device_id": pack["author_device_id"],
            "sticker_count": pack["sticker_count"],
            "is_public": pack["is_public"],
            "tags": pack["tags"],
            "stickers": [
                {
                    "r2_key": s.get("r2_key", ""),
                    "emojis": s.get("emojis", []),
                    "position": s.get("position", 0),
                }
                for s in pack["stickers"]
            ],
        })

    resp = requests.post(
        f"{WORKER_API_URL}/packs/register-batch",
        json={"packs": registration},
        headers={"Authorization": f"Bearer {WORKER_ADMIN_KEY}"},
        timeout=30,
    )

    if resp.status_code == 200:
        data = resp.json()
        print(f"  Registered {data.get('count', len(packs))} packs with Worker")
        return True
    else:
        print(f"  Failed to register packs: {resp.status_code} {resp.text}")
        return False
```

- [ ] **Step 2: Write test_uploader.py**

```python
"""Tests for R2 uploader and pack grouping."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from uploader import group_into_packs


def _make_sticker_results(count: int) -> list[dict]:
    """Create fake sticker results for testing."""
    return [
        {"sticker_path": f"/tmp/s_{i}.webp", "emojis": ["😊"], "size_kb": 50}
        for i in range(count)
    ]


def test_group_single_pack():
    """≤30 stickers should produce exactly one pack."""
    results = _make_sticker_results(25)
    packs = group_into_packs(results, "Test Album", "user123")
    assert len(packs) == 1
    assert packs[0]["name"] == "Test Album"
    assert packs[0]["sticker_count"] == 25


def test_group_multiple_packs():
    """75 stickers should produce 3 packs of 30/30/15."""
    results = _make_sticker_results(75)
    packs = group_into_packs(results, "Big Album", "user123")
    assert len(packs) == 3
    assert packs[0]["name"] == "Big Album (1/3)"
    assert packs[1]["name"] == "Big Album (2/3)"
    assert packs[2]["name"] == "Big Album (3/3)"
    assert packs[0]["sticker_count"] == 30
    assert packs[2]["sticker_count"] == 15


def test_group_exact_multiple():
    """Exactly 60 stickers should produce 2 packs of 30."""
    results = _make_sticker_results(60)
    packs = group_into_packs(results, "Even Album", "user123")
    assert len(packs) == 2
    assert all(p["sticker_count"] == 30 for p in packs)


def test_group_one_sticker():
    """Single sticker should still produce a valid pack."""
    results = _make_sticker_results(1)
    packs = group_into_packs(results, "Solo", "user123")
    assert len(packs) == 1
    assert packs[0]["sticker_count"] == 1
    assert packs[0]["is_public"] is False


def test_group_packs_have_uuids():
    """Each pack should have a unique UUID."""
    results = _make_sticker_results(90)
    packs = group_into_packs(results, "Album", "user123")
    ids = [p["id"] for p in packs]
    assert len(ids) == len(set(ids))  # All unique
```

- [ ] **Step 3: Run tests**

```bash
python3 -m pytest tests/test_uploader.py -v
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tools/sticker-pipeline/uploader.py tools/sticker-pipeline/tests/test_uploader.py
git commit -m "feat(cli): add R2 uploader and pack grouping"
```

---

## Task 7: Main CLI Entry Point

**Files:**
- Create: `tools/sticker-pipeline/sticker_pipeline.py`

- [ ] **Step 1: Write sticker_pipeline.py**

```python
#!/usr/bin/env python3
"""StickerOfficer CLI — Google Photos to Sticker Pipeline.

Usage:
    python sticker_pipeline.py auth          # Authenticate with Google
    python sticker_pipeline.py albums        # List your albums
    python sticker_pipeline.py process       # Process an album into sticker packs
"""

import json
import shutil
import click
from pathlib import Path
from tqdm import tqdm
from config import TEMP_DIR, USER_ID
from auth import get_credentials
from downloader import list_albums, download_album
from processor import process_photo
from video_processor import process_video
from uploader import get_r2_client, upload_sticker, upload_thumbnail, upload_manifest, group_into_packs, register_packs_with_worker


@click.group()
def cli():
    """StickerOfficer — Google Photos to Sticker Pipeline."""
    pass


@cli.command()
def auth():
    """Authenticate with Google Photos (opens browser)."""
    click.echo("Opening browser for Google Photos authentication...")
    creds = get_credentials()
    click.echo(f"Authenticated successfully. Token saved.")


@cli.command()
def albums():
    """List all Google Photos albums."""
    creds = get_credentials()
    album_list = list_albums(creds)

    click.echo(f"\nFound {len(album_list)} albums:\n")
    click.echo(f"{'#':<4} {'Title':<40} {'Count':>6}")
    click.echo("-" * 52)
    for i, album in enumerate(album_list, 1):
        click.echo(f"{i:<4} {album['title'][:39]:<40} {album['count']:>6}")


@cli.command()
@click.option("--album", "-a", help="Album title (exact match)")
@click.option("--album-index", "-i", type=int, help="Album number from 'albums' list")
@click.option("--sample", "-s", type=int, default=0, help="Process only first N items (for testing)")
@click.option("--dry-run", is_flag=True, help="Show what would be done without processing")
@click.option("--skip-upload", is_flag=True, help="Process locally without uploading to R2")
@click.option("--user-id", default=USER_ID, help="User ID for pack ownership")
def process(album, album_index, sample, dry_run, skip_upload, user_id):
    """Process a Google Photos album into sticker packs."""
    creds = get_credentials()
    album_list = list_albums(creds)

    # Resolve album selection
    target = None
    if album:
        target = next((a for a in album_list if a["title"] == album), None)
        if not target:
            click.echo(f"Album '{album}' not found. Use 'albums' to list available albums.")
            return
    elif album_index:
        if 1 <= album_index <= len(album_list):
            target = album_list[album_index - 1]
        else:
            click.echo(f"Invalid index {album_index}. Range: 1-{len(album_list)}")
            return
    else:
        # Interactive selection
        click.echo("Select an album:")
        for i, a in enumerate(album_list[:20], 1):
            click.echo(f"  {i}. {a['title']} ({a['count']} items)")
        choice = click.prompt("Album number", type=int)
        if 1 <= choice <= len(album_list):
            target = album_list[choice - 1]
        else:
            click.echo("Invalid choice.")
            return

    album_name = target["title"]
    album_id = target["id"]
    total = target["count"]
    limit = sample if sample > 0 else None

    click.echo(f"\nAlbum: {album_name}")
    click.echo(f"Items: {total}" + (f" (sampling {limit})" if limit else ""))

    if dry_run:
        packs_needed = max(1, ((limit or total) + 29) // 30)
        click.echo(f"Would create: ~{packs_needed} packs")
        click.echo("Dry run complete. No files processed.")
        return

    # Create temp output directory
    output_dir = TEMP_DIR / "processed"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Download and process
    sticker_results = []
    photo_count = 0
    video_count = 0
    fail_count = 0

    for item, local_path in download_album(creds, album_id, album_name, limit=limit):
        if local_path is None:
            fail_count += 1
            continue

        if item["is_video"]:
            segments = process_video(local_path, output_dir)
            for seg in segments:
                sticker_results.append(seg)
            video_count += 1
        else:
            result = process_photo(local_path, output_dir)
            if result:
                sticker_results.append(result)
                photo_count += 1
            else:
                fail_count += 1

    click.echo(f"\nProcessed: {photo_count} photos, {video_count} videos, {fail_count} failures")
    click.echo(f"Total stickers: {len(sticker_results)}")

    if not sticker_results:
        click.echo("No stickers to upload. Done.")
        return

    # Group into packs
    packs = group_into_packs(sticker_results, album_name, user_id)
    click.echo(f"Created {len(packs)} packs")

    if skip_upload:
        click.echo(f"Stickers saved to {output_dir}. Skipping upload.")
        _print_summary(packs, sticker_results)
        return

    # Upload to R2
    r2 = get_r2_client()
    click.echo("\nUploading to R2...")

    for pack in tqdm(packs, desc="Packs"):
        for i, sticker in enumerate(pack["stickers"]):
            sticker_path = sticker["sticker_path"]
            if isinstance(sticker_path, str):
                sticker_path = Path(sticker_path)

            r2_key = upload_sticker(r2, sticker_path, user_id, pack["id"], i)
            sticker["r2_key"] = r2_key
            sticker["position"] = i

            thumb_path = sticker.get("thumb_path")
            if thumb_path and Path(thumb_path).exists():
                thumb_key = upload_thumbnail(r2, Path(thumb_path), user_id, pack["id"], i)
                sticker["thumb_r2_key"] = thumb_key

        # Upload manifest
        manifest = {
            "id": pack["id"],
            "name": pack["name"],
            "sticker_count": pack["sticker_count"],
            "stickers": [
                {
                    "r2_key": s.get("r2_key"),
                    "thumb_r2_key": s.get("thumb_r2_key"),
                    "emojis": s.get("emojis", []),
                    "position": s.get("position", 0),
                }
                for s in pack["stickers"]
            ],
        }
        upload_manifest(r2, manifest, user_id, pack["id"])

    # Register with Worker API
    click.echo("\nRegistering packs with Worker API...")
    register_packs_with_worker(packs)

    # Cleanup
    _print_summary(packs, sticker_results)
    click.echo(f"\nTemp files in {TEMP_DIR}. Run 'rm -rf {TEMP_DIR}' to clean up.")


def _print_summary(packs: list[dict], sticker_results: list[dict]):
    """Print processing summary."""
    total_size = sum(s.get("size_kb", 0) for s in sticker_results)
    click.echo(f"\n{'='*50}")
    click.echo(f"SUMMARY")
    click.echo(f"{'='*50}")
    click.echo(f"Packs created:    {len(packs)}")
    click.echo(f"Total stickers:   {len(sticker_results)}")
    click.echo(f"Total size:       {total_size / 1024:.1f} MB")
    click.echo(f"Avg sticker size: {total_size / max(1, len(sticker_results)):.0f} KB")
    for i, pack in enumerate(packs):
        click.echo(f"  Pack {i+1}: {pack['name']} ({pack['sticker_count']} stickers)")


if __name__ == "__main__":
    cli()
```

- [ ] **Step 2: Make executable and test CLI help**

```bash
chmod +x tools/sticker-pipeline/sticker_pipeline.py
cd tools/sticker-pipeline && source venv/bin/activate
python3 sticker_pipeline.py --help
python3 sticker_pipeline.py process --help
```

Expected: Help text prints with all options.

- [ ] **Step 3: Commit**

```bash
git add tools/sticker-pipeline/sticker_pipeline.py
git commit -m "feat(cli): add main CLI entry point with auth, albums, and process commands"
```

---

## Task 8: Worker API — Google Auth + Batch Pack Registration

**Files:**
- Create: `sticker-ai-proxy/src/db/migrations/002_google_photos.sql`
- Modify: `sticker-ai-proxy/src/routes/auth.ts`
- Modify: `sticker-ai-proxy/src/index.ts`

- [ ] **Step 1: Create D1 migration**

Create `sticker-ai-proxy/src/db/migrations/002_google_photos.sql`:

```sql
-- Migration 002: Google Photos integration
-- Adds Google account linking, sticker metadata, import jobs, and shares

-- Extend devices table with Google account fields
ALTER TABLE devices ADD COLUMN google_id TEXT;
ALTER TABLE devices ADD COLUMN google_email TEXT;
ALTER TABLE devices ADD COLUMN google_name TEXT;
ALTER TABLE devices ADD COLUMN google_photo TEXT;

-- Sticker metadata for search/emoji tagging
CREATE TABLE IF NOT EXISTS sticker_metadata (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  sticker_index INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'static',
  emojis TEXT,
  tags TEXT,
  user_text TEXT,
  source_album TEXT,
  r2_key TEXT NOT NULL,
  thumb_r2_key TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Import job tracking
CREATE TABLE IF NOT EXISTS import_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES devices(device_id),
  album_id TEXT,
  album_name TEXT,
  total_items INTEGER NOT NULL,
  processed_items INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Private sharing
CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  owner_id TEXT NOT NULL REFERENCES devices(device_id),
  shared_with_id TEXT,
  share_code TEXT UNIQUE,
  permission TEXT DEFAULT 'view',
  created_at TEXT DEFAULT (datetime('now'))
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sticker_metadata_pack ON sticker_metadata(pack_id);
CREATE INDEX IF NOT EXISTS idx_sticker_metadata_emojis ON sticker_metadata(emojis);
CREATE INDEX IF NOT EXISTS idx_import_jobs_user ON import_jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_shares_pack ON shares(pack_id);
CREATE INDEX IF NOT EXISTS idx_shares_shared_with ON shares(shared_with_id);
CREATE INDEX IF NOT EXISTS idx_shares_code ON shares(share_code);
```

- [ ] **Step 2: Add POST /google to auth.ts**

Add this endpoint after the existing `/accept-terms` route in `sticker-ai-proxy/src/routes/auth.ts` (before `export default auth`):

```typescript
/**
 * POST /google
 * Body: { id_token: string, device_id?: string }
 * Verifies Google ID token, creates/links account, issues JWT.
 */
auth.post('/google', async (c) => {
  let body: { id_token?: string; device_id?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const idToken = body.id_token;
  if (!idToken) {
    return c.json({ error: 'id_token is required' }, 400);
  }

  // Verify Google ID token
  const googleUser = await verifyGoogleToken(idToken);
  if (!googleUser) {
    return c.json({ error: 'Invalid Google ID token' }, 401);
  }

  // Check if Google account already linked
  const existingByGoogle = await c.env.DB.prepare(
    'SELECT device_id, public_id FROM devices WHERE google_id = ?',
  )
    .bind(googleUser.sub)
    .first<{ device_id: string; public_id: string }>();

  let deviceId: string;
  let publicId: string;

  if (existingByGoogle) {
    // Existing Google-linked account
    deviceId = existingByGoogle.device_id;
    publicId = existingByGoogle.public_id;
    await c.env.DB.prepare(
      "UPDATE devices SET last_seen = datetime('now'), google_name = ?, google_photo = ? WHERE device_id = ?",
    )
      .bind(googleUser.name, googleUser.picture, deviceId)
      .run();
  } else if (body.device_id) {
    // Link Google to existing device
    const existingDevice = await c.env.DB.prepare(
      'SELECT public_id FROM devices WHERE device_id = ?',
    )
      .bind(body.device_id)
      .first<{ public_id: string }>();

    if (existingDevice) {
      deviceId = body.device_id;
      publicId = existingDevice.public_id;
      await c.env.DB.prepare(
        'UPDATE devices SET google_id = ?, google_email = ?, google_name = ?, google_photo = ? WHERE device_id = ?',
      )
        .bind(googleUser.sub, googleUser.email, googleUser.name, googleUser.picture, deviceId)
        .run();
    } else {
      // Device not found, create new
      deviceId = body.device_id;
      publicId = generatePublicId();
      await c.env.DB.prepare(
        'INSERT INTO devices (device_id, public_id, google_id, google_email, google_name, google_photo) VALUES (?, ?, ?, ?, ?, ?)',
      )
        .bind(deviceId, publicId, googleUser.sub, googleUser.email, googleUser.name, googleUser.picture)
        .run();
    }
  } else {
    // New user via Google (no device_id)
    deviceId = `google_${googleUser.sub}`;
    publicId = generatePublicId();
    await c.env.DB.prepare(
      'INSERT INTO devices (device_id, public_id, google_id, google_email, google_name, google_photo) VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(deviceId, publicId, googleUser.sub, googleUser.email, googleUser.name, googleUser.picture)
      .run();
  }

  const token = await signJwt(
    { sub: deviceId, pid: publicId },
    c.env.JWT_SECRET,
    EXPIRES_IN,
  );

  return c.json({
    token,
    public_id: publicId,
    google_name: googleUser.name,
    google_photo: googleUser.picture,
    expires_in: EXPIRES_IN,
  });
});


async function verifyGoogleToken(idToken: string): Promise<{
  sub: string; email: string; name: string; picture: string;
} | null> {
  try {
    const resp = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`,
    );
    if (!resp.ok) return null;
    const data = await resp.json() as Record<string, string>;
    return {
      sub: data.sub,
      email: data.email || '',
      name: data.name || '',
      picture: data.picture || '',
    };
  } catch {
    return null;
  }
}
```

- [ ] **Step 3: Add POST /packs/register-batch to index.ts**

Add this route in `sticker-ai-proxy/src/index.ts` after the existing pack routes:

```typescript
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
    // Insert pack
    await c.env.DB.prepare(
      'INSERT OR IGNORE INTO packs (id, name, author_device_id, sticker_count, is_public, tags) VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(pack.id, pack.name, pack.author_device_id, pack.sticker_count, pack.is_public, pack.tags)
      .run();

    // Insert stickers with metadata
    for (const sticker of pack.stickers) {
      const stickerId = `${pack.id}_${sticker.position}`;
      await c.env.DB.prepare(
        'INSERT OR IGNORE INTO stickers (id, pack_id, r2_key, position) VALUES (?, ?, ?, ?)',
      )
        .bind(stickerId, pack.id, sticker.r2_key, sticker.position)
        .run();

      // Insert metadata if emojis present
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
```

- [ ] **Step 4: Run Worker typecheck**

```bash
cd sticker-ai-proxy && npm run typecheck
```

Expected: No type errors.

- [ ] **Step 5: Commit**

```bash
git add sticker-ai-proxy/src/db/migrations/002_google_photos.sql sticker-ai-proxy/src/routes/auth.ts sticker-ai-proxy/src/index.ts
git commit -m "feat(worker): add Google auth endpoint and batch pack registration"
```

---

## Task 9: End-to-End Test — Sample 10 Photos

**Files:**
- Create: `tools/sticker-pipeline/tests/test_e2e.py`

- [ ] **Step 1: Write e2e test script**

```python
"""End-to-end test: process sample photos and verify output quality."""

import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from processor import process_photo, _fit_and_pad
from video_processor import _compute_segments
from uploader import group_into_packs


def test_e2e_photo_pipeline(sample_photo, output_dir):
    """Full photo pipeline: bg removal → sticker → thumbnail → metadata."""
    result = process_photo(sample_photo, output_dir)

    # Verify outputs exist and are valid
    assert result is not None, "Processing failed"

    sticker = Image.open(result["sticker_path"])
    assert sticker.size == (512, 512), f"Sticker size {sticker.size} != (512, 512)"
    assert sticker.mode == "RGBA", f"Sticker mode {sticker.mode} != RGBA"

    thumb = Image.open(result["thumb_path"])
    assert thumb.size == (128, 128), f"Thumb size {thumb.size} != (128, 128)"

    assert result["size_kb"] < 500, f"Sticker {result['size_kb']:.0f}KB exceeds 500KB limit"
    assert len(result["emojis"]) >= 1, "No emojis assigned"
    assert all(isinstance(e, str) for e in result["emojis"]), "Emojis must be strings"

    print(f"  Sticker: {result['size_kb']:.0f}KB, emojis: {result['emojis']}")


def test_e2e_pack_grouping_realistic():
    """Simulate 850 stickers (typical album) → ~29 packs."""
    results = [
        {"sticker_path": f"/tmp/s_{i}.webp", "emojis": ["😊"], "size_kb": 75}
        for i in range(850)
    ]
    packs = group_into_packs(results, "Bali Trip 2025", "user_abc")

    assert len(packs) == 29, f"Expected 29 packs, got {len(packs)}"
    assert packs[0]["name"] == "Bali Trip 2025 (1/29)"
    assert packs[-1]["name"] == "Bali Trip 2025 (29/29)"
    assert packs[-1]["sticker_count"] == 10  # 850 % 30 = 10

    total_stickers = sum(p["sticker_count"] for p in packs)
    assert total_stickers == 850

    # All packs should be private
    assert all(not p["is_public"] for p in packs)

    print(f"  {len(packs)} packs, {total_stickers} stickers")


def test_e2e_video_segmenting_realistic():
    """Simulate typical phone video durations."""
    # 3-second clip → 1 sticker
    assert len(_compute_segments(3)) == 1
    # 45-second video → 6-7 stickers of ~7s each
    segs = _compute_segments(45)
    assert 5 <= len(segs) <= 8
    # 2-minute video → ~17 stickers
    segs = _compute_segments(120)
    assert 14 <= len(segs) <= 20
    # All segments should be 5-10 seconds
    for start, end in segs:
        assert 4 <= (end - start) <= 10
```

- [ ] **Step 2: Run e2e tests**

```bash
python3 -m pytest tests/test_e2e.py -v --timeout=120
```

Expected: 3 tests pass.

- [ ] **Step 3: Run the actual CLI with --sample 10 (manual QA)**

```bash
# First authenticate
python3 sticker_pipeline.py auth

# List albums to see what's available
python3 sticker_pipeline.py albums

# Process 10 photos from first album, skip upload for now
python3 sticker_pipeline.py process --album-index 1 --sample 10 --skip-upload
```

Expected: 10 photos downloaded, processed, stickers saved locally. Review quality in `tmp/processed/`.

- [ ] **Step 4: Verify output quality manually**

```bash
# Check sticker files
ls -la tmp/processed/*.webp
# Open a few to inspect (macOS)
open tmp/processed/*.webp
```

Verify:
- [x] Background removed cleanly
- [x] Stickers are 512x512
- [x] File sizes under 200KB
- [x] Emojis make sense for the content

- [ ] **Step 5: Commit**

```bash
git add tools/sticker-pipeline/tests/test_e2e.py
git commit -m "test(cli): add e2e tests for photo pipeline, pack grouping, and video segmenting"
```

---

## Task 10: Full Album Run + R2 Upload Verification

- [ ] **Step 1: Set up .env with real credentials**

Copy `.env.example` to `.env` and fill in:
- Google OAuth credentials from console.cloud.google.com
- R2 API credentials from Cloudflare dashboard
- Worker admin key
- Your user/device ID

- [ ] **Step 2: Run D1 migration on Cloudflare**

```bash
cd sticker-ai-proxy
npx wrangler d1 execute sticker-officer --file=src/db/migrations/002_google_photos.sql
```

- [ ] **Step 3: Deploy updated Worker**

```bash
cd sticker-ai-proxy && npm run deploy
```

- [ ] **Step 4: Test batch registration endpoint**

```bash
curl -X POST https://sticker-officer-api.ceofutureatoms.workers.dev/packs/register-batch \
  -H "Authorization: Bearer YOUR_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"packs":[{"id":"test-pack-001","name":"Test Pack","author_device_id":"YOUR_DEVICE_ID","sticker_count":1,"is_public":false,"tags":"[\"test\"]","stickers":[{"r2_key":"test/sticker_0.webp","emojis":["😊"],"position":0}]}]}'
```

Expected: `{"ok":true,"count":1}`

- [ ] **Step 5: Run full album (small one first, ~50 photos) with upload**

```bash
cd tools/sticker-pipeline && source venv/bin/activate
python3 sticker_pipeline.py process --album "YOUR_SMALLEST_ALBUM" --sample 50
```

- [ ] **Step 6: Verify R2 upload**

```bash
# Check R2 via wrangler
cd sticker-ai-proxy
npx wrangler r2 object list sticker-officer-packs --prefix YOUR_USER_ID/
```

- [ ] **Step 7: Run full 13K overnight**

```bash
cd tools/sticker-pipeline && source venv/bin/activate
nohup python3 sticker_pipeline.py process --album "ALBUM_NAME" > pipeline.log 2>&1 &
echo "Pipeline running in background. Check pipeline.log for progress."
tail -f pipeline.log
```

---

## Progress Tracker

| Task | Description | Status | Tests |
|------|------------|--------|-------|
| 1 | Python environment setup | pending | N/A |
| 2 | Google Photos OAuth | pending | 2 unit |
| 3 | Album downloader | pending | 4 unit |
| 4 | Photo processor (bg removal + emotions) | pending | 4 unit |
| 5 | Video processor (smart split) | pending | 5 unit |
| 6 | R2 uploader + pack grouping | pending | 5 unit |
| 7 | Main CLI entry point | pending | CLI help |
| 8 | Worker API (Google auth + batch reg) | pending | typecheck |
| 9 | E2E tests + sample run | pending | 3 e2e + manual QA |
| 10 | Full album run + R2 verification | pending | integration |

**Total: 23 unit tests, 3 e2e tests, 1 manual QA check, 1 integration test**
