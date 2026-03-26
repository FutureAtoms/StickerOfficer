#!/usr/bin/env python3
"""StickerOfficer CLI - Google Photos to Sticker Pipeline.

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
    """StickerOfficer - Google Photos to Sticker Pipeline."""
    pass


@cli.command()
def auth():
    """Authenticate with Google Photos (opens browser)."""
    click.echo("Opening browser for Google Photos authentication...")
    creds = get_credentials()
    click.echo("Authenticated successfully. Token saved.")


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

    click.echo("\nRegistering packs with Worker API...")
    register_packs_with_worker(packs)

    _print_summary(packs, sticker_results)
    click.echo(f"\nTemp files in {TEMP_DIR}. Run 'rm -rf {TEMP_DIR}' to clean up.")


def _print_summary(packs: list[dict], sticker_results: list[dict]):
    """Print processing summary."""
    total_size = sum(s.get("size_kb", 0) for s in sticker_results)
    click.echo(f"\n{'='*50}")
    click.echo("SUMMARY")
    click.echo(f"{'='*50}")
    click.echo(f"Packs created:    {len(packs)}")
    click.echo(f"Total stickers:   {len(sticker_results)}")
    click.echo(f"Total size:       {total_size / 1024:.1f} MB")
    click.echo(f"Avg sticker size: {total_size / max(1, len(sticker_results)):.0f} KB")
    for i, pack in enumerate(packs):
        click.echo(f"  Pack {i+1}: {pack['name']} ({pack['sticker_count']} stickers)")


if __name__ == "__main__":
    cli()
