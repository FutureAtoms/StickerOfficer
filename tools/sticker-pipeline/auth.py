"""Google Photos OAuth authentication."""

import json
from pathlib import Path
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from config import GOOGLE_SCOPES, TOKEN_FILE, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET


def get_credentials() -> Credentials:
    """Get valid Google OAuth credentials.

    Priority:
    1. Existing saved token (from previous successful auth)
    2. Fresh OAuth flow using GOOGLE_CLIENT_ID/SECRET from .env
    """
    creds = None

    # Try saved token first
    if TOKEN_FILE.exists():
        try:
            creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), GOOGLE_SCOPES)
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
                _save_token(creds)
                return creds
            if creds and creds.valid:
                return creds
        except Exception:
            # Token file is stale/invalid — delete and re-auth
            TOKEN_FILE.unlink(missing_ok=True)
            creds = None

    # Fresh OAuth flow
    creds = _run_oauth_flow()
    _save_token(creds)
    return creds


def _run_oauth_flow() -> Credentials:
    """Run the OAuth installed-app flow (opens browser)."""
    from google_auth_oauthlib.flow import InstalledAppFlow

    if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
        raise RuntimeError(
            "Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env\n"
            "Create a Desktop OAuth client at console.cloud.google.com"
        )

    client_config = {
        "installed": {
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }
    flow = InstalledAppFlow.from_client_config(client_config, GOOGLE_SCOPES)
    return flow.run_local_server(port=8089, open_browser=True)


def _save_token(creds: Credentials) -> None:
    """Persist credentials to disk."""
    TOKEN_FILE.write_text(json.dumps({
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": list(creds.scopes) if creds.scopes else [],
    }))
