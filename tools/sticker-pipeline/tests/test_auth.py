"""Tests for Google Photos OAuth."""

import json
from unittest.mock import patch, MagicMock
from pathlib import Path
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
