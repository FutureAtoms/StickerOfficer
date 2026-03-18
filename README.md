# StickerOfficer

AI-powered sticker maker for WhatsApp & Telegram. Create, share, and discover amazing stickers.

## Features

- **AI Sticker Generation** — Describe a sticker in text, get 4 AI-generated variations
- **One-Click WhatsApp Export** — Seamless sticker pack sharing to WhatsApp
- **AI Background Removal** — On-device ONNX-powered instant bg removal
- **AI Style Transfer** — Cartoon, anime, pixel art, watercolor, pop art styles
- **Smart Captions** — AI-suggested witty captions and meme text
- **Sticker Editor** — Full canvas editor with brush, lasso, eraser, text, transforms
- **Social Feed** — Discover trending stickers, follow creators, like packs
- **Weekly Challenges** — Community sticker contests with featured winners
- **Sticker Packs** — Organize, manage, and publish sticker collections

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (iOS + Android) |
| State | Riverpod 2.x |
| Backend | Firebase (Auth, Firestore, Storage, Functions) |
| AI (on-device) | ONNX Runtime |
| AI (cloud) | Hugging Face Inference API |
| Monetization | AdMob + RevenueCat |

## Getting Started

```bash
# Clone
git clone https://github.com/FutureAtoms/StickerOfficer.git
cd StickerOfficer

# Install Flutter dependencies
flutter pub get

# Set up Firebase (requires FlutterFire CLI)
flutterfire configure

# Run
flutter run

# Cloud Functions
cd functions
npm install
npm run build
```

## Project Structure

```
lib/
├── main.dart              # Entry point
├── app.dart               # MaterialApp with theme & routing
├── core/                  # Shared constants, theme, widgets
└── features/              # Feature modules
    ├── auth/              # Login, onboarding
    ├── editor/            # Sticker canvas editor
    ├── ai_generate/       # Text-to-sticker AI
    ├── ai_style/          # Style transfer
    ├── feed/              # Social inspiration feed
    ├── search/            # Search & categories
    ├── packs/             # Sticker pack management
    ├── export/            # WhatsApp/Telegram export
    ├── challenges/        # Weekly contests
    ├── profile/           # User profiles
    └── premium/           # Monetization
```

## License

MIT — see [LICENSE](LICENSE)
