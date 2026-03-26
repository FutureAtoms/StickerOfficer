"""Download media items from Google Photos albums."""

import time
from pathlib import Path
from typing import Generator
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
from tqdm import tqdm
import requests as http_requests
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
        resp = http_requests.get(url, timeout=120)
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
