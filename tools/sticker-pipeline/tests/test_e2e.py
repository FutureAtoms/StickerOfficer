"""End-to-end test: process sample photos and verify output quality."""

import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from processor import process_photo
from video_processor import _compute_segments
from uploader import group_into_packs


def test_e2e_photo_pipeline(sample_photo, output_dir):
    """Full photo pipeline: bg removal -> sticker -> thumbnail -> metadata."""
    result = process_photo(sample_photo, output_dir)

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
    """Simulate 850 stickers (typical album) -> ~29 packs."""
    results = [
        {"sticker_path": f"/tmp/s_{i}.webp", "emojis": ["\U0001f60a"], "size_kb": 75}
        for i in range(850)
    ]
    packs = group_into_packs(results, "Bali Trip 2025", "user_abc")

    assert len(packs) == 29, f"Expected 29 packs, got {len(packs)}"
    assert packs[0]["name"] == "Bali Trip 2025 (1/29)"
    assert packs[-1]["name"] == "Bali Trip 2025 (29/29)"
    assert packs[-1]["sticker_count"] == 10

    total_stickers = sum(p["sticker_count"] for p in packs)
    assert total_stickers == 850
    assert all(not p["is_public"] for p in packs)


def test_e2e_video_segmenting_realistic():
    """Simulate typical phone video durations."""
    assert len(_compute_segments(3)) == 1
    segs = _compute_segments(45)
    assert 5 <= len(segs) <= 8
    segs = _compute_segments(120)
    assert 14 <= len(segs) <= 20
    for start, end in segs:
        assert 4 <= (end - start) <= 10
