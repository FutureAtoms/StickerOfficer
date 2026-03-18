# StickerOfficer — AI-Powered Sticker Maker

## Project Overview
Flutter app for creating, sharing, and discovering stickers for WhatsApp & Telegram.
Firebase backend with Cloud Functions. On-device AI via ONNX. Cloud AI via Hugging Face.

## Tech Stack
- **Frontend**: Flutter 3.24+ / Dart 3.2+
- **State**: Riverpod 2.x
- **Routing**: GoRouter
- **Backend**: Firebase (Auth, Firestore, Storage, Functions, Messaging)
- **AI (on-device)**: ONNX Runtime (bg removal, style transfer)
- **AI (cloud)**: Hugging Face Inference API (text-to-sticker)
- **Monetization**: AdMob + RevenueCat

## Architecture
- Feature-first folder structure: `lib/features/{feature}/{data,domain,presentation}/`
- Shared code in `lib/core/` (constants, theme, widgets, utils)
- Services in `lib/services/`
- Cloud Functions in `functions/src/` (TypeScript)

## Key Commands
```bash
flutter pub get          # Install dependencies
flutter analyze          # Lint check
flutter test             # Run tests
flutter run              # Run on device/emulator
flutter build apk        # Build Android
flutter build ios        # Build iOS
cd functions && npm run build  # Build Cloud Functions
```

## Code Conventions
- Use Riverpod providers for state (no setState except local animation state)
- All colors in `core/constants/app_colors.dart`
- All typography via `AppTypography` (Nunito font)
- Min touch target: 48x48dp, prefer 56x56dp
- Border radius: 16-24px cards, 28px buttons
- WhatsApp export button must be the most prominent action on pack screens
- Use `BubblyButton` and `WhatsAppButton` widgets for consistency
- Keep screens in their feature folder's `presentation/` directory

## Priority #1: WhatsApp Integration
The WhatsApp export must be seamless one-click. The big green button should be
visible on every pack detail screen and my packs screen.

## Design System
- Primary gradient: coral (#FF6B6B) → purple (#A855F7)
- Secondary: teal (#06D6A0)
- Background: warm white (#FFF8F0)
- Font: Nunito (rounded, bubbly)
- Everything rounded, generous spacing, bottom-sheet-first UX
