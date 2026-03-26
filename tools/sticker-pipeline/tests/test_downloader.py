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
