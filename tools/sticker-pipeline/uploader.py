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
