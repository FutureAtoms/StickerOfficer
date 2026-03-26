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
    assert result.getpixel((0, 0))[3] == 0
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

    sticker = Image.open(result["sticker_path"])
    assert sticker.size == (512, 512)

    thumb = Image.open(result["thumb_path"])
    assert thumb.size == (128, 128)

    assert len(result["emojis"]) >= 1
    assert result["size_kb"] > 0
