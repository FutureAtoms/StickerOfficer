"""Shared test fixtures."""

import pytest
from pathlib import Path
from PIL import Image


@pytest.fixture
def sample_photo(tmp_path) -> Path:
    """Create a 1024x768 test photo with a colored rectangle (simulates person)."""
    img = Image.new("RGB", (1024, 768), color=(200, 200, 200))
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
