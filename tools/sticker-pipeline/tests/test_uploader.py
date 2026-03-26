"""Tests for R2 uploader and pack grouping."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from uploader import group_into_packs


def _make_sticker_results(count: int) -> list[dict]:
    return [
        {"sticker_path": f"/tmp/s_{i}.webp", "emojis": ["\U0001f60a"], "size_kb": 50}
        for i in range(count)
    ]


def test_group_single_pack():
    results = _make_sticker_results(25)
    packs = group_into_packs(results, "Test Album", "user123")
    assert len(packs) == 1
    assert packs[0]["name"] == "Test Album"
    assert packs[0]["sticker_count"] == 25


def test_group_multiple_packs():
    results = _make_sticker_results(75)
    packs = group_into_packs(results, "Big Album", "user123")
    assert len(packs) == 3
    assert packs[0]["name"] == "Big Album (1/3)"
    assert packs[1]["name"] == "Big Album (2/3)"
    assert packs[2]["name"] == "Big Album (3/3)"
    assert packs[0]["sticker_count"] == 30
    assert packs[2]["sticker_count"] == 15


def test_group_exact_multiple():
    results = _make_sticker_results(60)
    packs = group_into_packs(results, "Even Album", "user123")
    assert len(packs) == 2
    assert all(p["sticker_count"] == 30 for p in packs)


def test_group_one_sticker():
    results = _make_sticker_results(1)
    packs = group_into_packs(results, "Solo", "user123")
    assert len(packs) == 1
    assert packs[0]["sticker_count"] == 1
    assert packs[0]["is_public"] is False


def test_group_packs_have_uuids():
    results = _make_sticker_results(90)
    packs = group_into_packs(results, "Album", "user123")
    ids = [p["id"] for p in packs]
    assert len(ids) == len(set(ids))
