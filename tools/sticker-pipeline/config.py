import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Paths
BASE_DIR = Path(__file__).parent
TEMP_DIR = BASE_DIR / "tmp"
CREDENTIALS_FILE = BASE_DIR / "google_credentials.json"
TOKEN_FILE = BASE_DIR / "google_token.json"

# Google OAuth
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_SCOPES = ["https://www.googleapis.com/auth/photoslibrary.readonly"]

# Cloudflare R2
R2_ACCOUNT_ID = os.getenv("R2_ACCOUNT_ID", "")
R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID", "")
R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY", "")
R2_BUCKET_NAME = os.getenv("R2_BUCKET_NAME", "sticker-officer-packs")
R2_ENDPOINT = f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Worker API
WORKER_API_URL = os.getenv("WORKER_API_URL", "https://sticker-officer-api.ceofutureatoms.workers.dev")
WORKER_ADMIN_KEY = os.getenv("WORKER_ADMIN_KEY", "")

# Processing
USER_ID = os.getenv("USER_ID", "")
STICKER_SIZE = 512
THUMB_SIZE = 128
PACK_SIZE = 30
WEBP_QUALITY = 85
MAX_ANIMATED_SIZE_KB = 500
MAX_ANIMATED_DURATION_SEC = 8
