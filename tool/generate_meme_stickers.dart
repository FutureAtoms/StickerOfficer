// ignore_for_file: avoid_print
/// Generates 5 meme sticker packs (30 stickers each = 150 total)
/// as 512x512 PNG files with transparent backgrounds.
///
/// Run: dart run tool/generate_meme_stickers.dart
library;

import 'dart:io';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Meme pack definitions — 2025/2026 viral meme themes
// ---------------------------------------------------------------------------

class MemePack {
  final String prefix;
  final String name;
  final List<MemeSticker> stickers;

  const MemePack({
    required this.prefix,
    required this.name,
    required this.stickers,
  });
}

class MemeSticker {
  final String text;
  final int bgColor; // ARGB
  final int fgColor; // ARGB
  final int accentColor; // ARGB
  final String shape; // circle, rounded_rect, star, speech_bubble, heart

  const MemeSticker({
    required this.text,
    this.bgColor = 0xFFFFD700,
    this.fgColor = 0xFF000000,
    this.accentColor = 0xFFFF6B6B,
    this.shape = 'rounded_rect',
  });
}

// Pack 1: Brainrot / Internet Slang (2025-2026 viral)
const brainrotPack = MemePack(
  prefix: 'brainrot_memes',
  name: 'Brainrot Memes',
  stickers: [
    MemeSticker(text: 'SKIBIDI', bgColor: 0xFF7C3AED, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'RIZZ', bgColor: 0xFFFF6B6B, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'NO CAP', bgColor: 0xFF06D6A0, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'SLAY', bgColor: 0xFFFF69B4, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'BUSSIN', bgColor: 0xFFFF8C00, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'BET', bgColor: 0xFF4169E1, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'GOATED', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'W', bgColor: 0xFF00FF7F, fgColor: 0xFF000000, shape: 'circle'),
    MemeSticker(text: 'L', bgColor: 0xFFFF0000, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'FANUM\nTAX', bgColor: 0xFFFFA500, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'SIGMA', bgColor: 0xFF1a1a2e, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'OHIO', bgColor: 0xFF8B0000, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'AURA\n+100', bgColor: 0xFF9B59B6, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'MID', bgColor: 0xFF808080, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'BASED', bgColor: 0xFF2ECC71, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'PERIODT', bgColor: 0xFFE91E63, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'VIBING', bgColor: 0xFF00BCD4, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'NPC', bgColor: 0xFF607D8B, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'MAIN\nCHARACTER', bgColor: 0xFFE040FB, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'ICK', bgColor: 0xFF795548, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'DELULU', bgColor: 0xFFFF80AB, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'CAUGHT\nIN 4K', bgColor: 0xFF263238, fgColor: 0xFFFF5722),
    MemeSticker(text: 'SAY\nLESS', bgColor: 0xFF3F51B5, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'ITS\nGIVING', bgColor: 0xFFAB47BC, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'RENT\nFREE', bgColor: 0xFF26A69A, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'UNDERSTOOD\nTHE\nASSIGNMENT', bgColor: 0xFFEC407A, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'YEET', bgColor: 0xFFFF5722, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'COOK', bgColor: 0xFFFF9800, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'LOWKEY', bgColor: 0xFF546E7A, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'HIGHKEY', bgColor: 0xFFFFEB3B, fgColor: 0xFF000000, shape: 'star'),
  ],
);

// Pack 2: Reaction Memes
const reactionPack = MemePack(
  prefix: 'reaction_memes',
  name: 'Reaction Memes',
  stickers: [
    MemeSticker(text: 'LMAO', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'DEAD', bgColor: 0xFF000000, fgColor: 0xFFFF0000, shape: 'circle'),
    MemeSticker(text: 'MOOD', bgColor: 0xFF9C27B0, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'SAME', bgColor: 0xFF2196F3, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'BRO\nWHAT', bgColor: 0xFFFF5722, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'IM\nWEAK', bgColor: 0xFFFF9800, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'NAHHH', bgColor: 0xFFE91E63, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'FR FR', bgColor: 0xFF4CAF50, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'ONG', bgColor: 0xFF00BCD4, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'CRYING', bgColor: 0xFF42A5F5, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'HELP', bgColor: 0xFFFF0000, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'JAIL', bgColor: 0xFF37474F, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'PAUSE', bgColor: 0xFFFF6F00, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'REAL', bgColor: 0xFF1B5E20, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'FACTS', bgColor: 0xFF283593, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'SHOOK', bgColor: 0xFFE040FB, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'YIKES', bgColor: 0xFFFF1744, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'BRUH', bgColor: 0xFF795548, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'SIS', bgColor: 0xFFFF80AB, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'TEA', bgColor: 0xFF4DB6AC, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'SPILL', bgColor: 0xFFBA68C8, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'BLESSED', bgColor: 0xFFFFD54F, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'TOXIC', bgColor: 0xFF76FF03, fgColor: 0xFF000000),
    MemeSticker(text: 'SALTY', bgColor: 0xFF90A4AE, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'PETTY', bgColor: 0xFFCE93D8, fgColor: 0xFF000000),
    MemeSticker(text: 'EXTRA', bgColor: 0xFFFF6E40, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'ICONIC', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'rounded_rect'),
    MemeSticker(text: 'SNATCHED', bgColor: 0xFFE91E63, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'VIBE\nCHECK', bgColor: 0xFF00E5FF, fgColor: 0xFF000000, shape: 'circle'),
    MemeSticker(text: 'SHEESH', bgColor: 0xFF651FFF, fgColor: 0xFFFFFFFF, shape: 'star'),
  ],
);

// Pack 3: AI & Tech Memes (2025-2026 specific)
const aiTechPack = MemePack(
  prefix: 'ai_tech_memes',
  name: 'AI & Tech Memes',
  stickers: [
    MemeSticker(text: 'AI\nDID IT', bgColor: 0xFF2196F3, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'ChatGPT\nMOMENT', bgColor: 0xFF00BFA5, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'PROMPT\nENGINEER', bgColor: 0xFF7C4DFF, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'CTRL+Z\nMY LIFE', bgColor: 0xFF455A64, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'DEBUG\nMODE', bgColor: 0xFFFF5722, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: '404\nNOT\nFOUND', bgColor: 0xFF37474F, fgColor: 0xFF00FF00),
    MemeSticker(text: 'STACK\nOVERFLOW', bgColor: 0xFFF48FB1, fgColor: 0xFF000000),
    MemeSticker(text: 'WORKS ON\nMY MACHINE', bgColor: 0xFF689F38, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'HALLUCIN\nATING', bgColor: 0xFFAB47BC, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'VIBE\nCODING', bgColor: 0xFF00E676, fgColor: 0xFF000000),
    MemeSticker(text: 'SHIP IT', bgColor: 0xFF2979FF, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'MERGE\nCONFLICT', bgColor: 0xFFFF1744, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'LGTM', bgColor: 0xFF00C853, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'WFH\nVIBES', bgColor: 0xFFFFAB40, fgColor: 0xFF000000, shape: 'rounded_rect'),
    MemeSticker(text: 'DEPLOY\nFRIDAY', bgColor: 0xFFD50000, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'IN MY\nERA', bgColor: 0xFFE040FB, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'TOUCH\nGRASS', bgColor: 0xFF4CAF50, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'WIFI\nDOWN', bgColor: 0xFF263238, fgColor: 0xFFFF5252),
    MemeSticker(text: 'LOW\nBATTERY', bgColor: 0xFFFF0000, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'DM ME', bgColor: 0xFF1565C0, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'SCREEN\nTIME', bgColor: 0xFF78909C, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'DEEP\nFAKE', bgColor: 0xFF880E4F, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'OPEN\nSOURCE', bgColor: 0xFF388E3C, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'API\nDOWN', bgColor: 0xFFBF360C, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'FEATURE\nNOT BUG', bgColor: 0xFF1A237E, fgColor: 0xFFFFEB3B, shape: 'speech_bubble'),
    MemeSticker(text: 'sudo\nFIX IT', bgColor: 0xFF212121, fgColor: 0xFF00FF00),
    MemeSticker(text: 'YOLO\nDEPLOY', bgColor: 0xFFFF6D00, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'COFFEE\nFIRST', bgColor: 0xFF6D4C41, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'INFINITE\nLOOP', bgColor: 0xFF311B92, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'CTRL+C\nCTRL+V', bgColor: 0xFF546E7A, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
  ],
);

// Pack 4: Wholesome / Positive Vibes
const wholesomePack = MemePack(
  prefix: 'wholesome_memes',
  name: 'Wholesome Vibes',
  stickers: [
    MemeSticker(text: 'YOU\nGOT THIS', bgColor: 0xFFFF6B6B, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'PROUD\nOF YOU', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'SENDING\nLOVE', bgColor: 0xFFFF69B4, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'BIG\nHUGS', bgColor: 0xFFFFAB91, fgColor: 0xFF000000, shape: 'circle'),
    MemeSticker(text: 'LEGEND', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'QUEEN', bgColor: 0xFFE040FB, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'KING', bgColor: 0xFF2196F3, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'SELF\nCARE', bgColor: 0xFFA5D6A7, fgColor: 0xFF000000, shape: 'heart'),
    MemeSticker(text: 'GRATEFUL', bgColor: 0xFFFFCC80, fgColor: 0xFF000000),
    MemeSticker(text: 'BESTIE', bgColor: 0xFFCE93D8, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'MAIN\nSQUEEZE', bgColor: 0xFFEF5350, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'GOOD\nVIBES\nONLY', bgColor: 0xFF26C6DA, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'SOFT\nHOURS', bgColor: 0xFFF8BBD0, fgColor: 0xFF880E4F),
    MemeSticker(text: 'NO BAD\nDAYS', bgColor: 0xFFFFEB3B, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'HEALING\nERA', bgColor: 0xFF80CBC4, fgColor: 0xFF000000),
    MemeSticker(text: 'GROWTH\nMINDSET', bgColor: 0xFF66BB6A, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'PEACE\nOUT', bgColor: 0xFF42A5F5, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'STAY\nGOLDEN', bgColor: 0xFFFFD700, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'BELIEVE', bgColor: 0xFF7E57C2, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'YOU\nMATTER', bgColor: 0xFFFF7043, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'KEEP\nGOING', bgColor: 0xFF26A69A, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'GLOWING', bgColor: 0xFFFFCA28, fgColor: 0xFF000000, shape: 'star'),
    MemeSticker(text: 'ANGEL', bgColor: 0xFFE1BEE7, fgColor: 0xFF4A148C, shape: 'circle'),
    MemeSticker(text: 'LOVE\nTHAT', bgColor: 0xFFEF5350, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'SO\nPROUD', bgColor: 0xFFAB47BC, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'SWEET', bgColor: 0xFFFF8A80, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'THANKS\nFAM', bgColor: 0xFF00ACC1, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'MISS\nYOU', bgColor: 0xFFBA68C8, fgColor: 0xFFFFFFFF, shape: 'heart'),
    MemeSticker(text: 'LETS\nGOOO', bgColor: 0xFFFF6D00, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'ILY', bgColor: 0xFFFF1744, fgColor: 0xFFFFFFFF, shape: 'heart'),
  ],
);

// Pack 5: Daily Life / Relatable
const dailyLifePack = MemePack(
  prefix: 'daily_life_memes',
  name: 'Daily Life',
  stickers: [
    MemeSticker(text: 'MONDAY\nMOOD', bgColor: 0xFF455A64, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'FRIDAY\nFEELS', bgColor: 0xFFFF6F00, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'NEED\nCOFFEE', bgColor: 0xFF795548, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'FOOD\nCOMA', bgColor: 0xFFFFA726, fgColor: 0xFF000000),
    MemeSticker(text: 'SNACK\nTIME', bgColor: 0xFFFF7043, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'NAPPING', bgColor: 0xFF90CAF9, fgColor: 0xFF1A237E, shape: 'circle'),
    MemeSticker(text: 'ON MY\nWAY', bgColor: 0xFF66BB6A, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'RUNNING\nLATE', bgColor: 0xFFFF5252, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'LEFT ON\nREAD', bgColor: 0xFF42A5F5, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'SCREEN\nBREAK', bgColor: 0xFF78909C, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'GYM\nARC', bgColor: 0xFFD32F2F, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'CHEAT\nDAY', bgColor: 0xFFFF9100, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'OUTFIT\nCHECK', bgColor: 0xFFAB47BC, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'BROKE', bgColor: 0xFF607D8B, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'PAY\nDAY', bgColor: 0xFF00C853, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'BORED', bgColor: 0xFFBDBDBD, fgColor: 0xFF424242),
    MemeSticker(text: 'DO NOT\nDISTURB', bgColor: 0xFFD50000, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'STUDYING', bgColor: 0xFF1565C0, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'PROCRAS\nTINATING', bgColor: 0xFFFF6E40, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'BRB', bgColor: 0xFF00BCD4, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'AFK', bgColor: 0xFF546E7A, fgColor: 0xFFFFFFFF, shape: 'circle'),
    MemeSticker(text: 'HANGRY', bgColor: 0xFFFF3D00, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'COZY\nSZN', bgColor: 0xFFBCAAA4, fgColor: 0xFF3E2723),
    MemeSticker(text: 'HOT\nTAKE', bgColor: 0xFFFF1744, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'OVERTHINK\nING', bgColor: 0xFF7986CB, fgColor: 0xFFFFFFFF),
    MemeSticker(text: 'ADULTING', bgColor: 0xFF8D6E63, fgColor: 0xFFFFFFFF, shape: 'rounded_rect'),
    MemeSticker(text: 'NO\nTHANKS', bgColor: 0xFFE53935, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'YES\nPLEASE', bgColor: 0xFF43A047, fgColor: 0xFFFFFFFF, shape: 'speech_bubble'),
    MemeSticker(text: 'CHAOTIC\nGOOD', bgColor: 0xFF6A1B9A, fgColor: 0xFFFFFFFF, shape: 'star'),
    MemeSticker(text: 'MAIN\nEVENT', bgColor: 0xFFFF6D00, fgColor: 0xFFFFFFFF, shape: 'star'),
  ],
);

// ---------------------------------------------------------------------------
// Image generation
// ---------------------------------------------------------------------------

img.Image generateSticker(MemeSticker sticker) {
  const size = 512;
  final canvas = img.Image(width: size, height: size, numChannels: 4);

  // Transparent background
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  // Extract colors
  final bgR = (sticker.bgColor >> 16) & 0xFF;
  final bgG = (sticker.bgColor >> 8) & 0xFF;
  final bgB = sticker.bgColor & 0xFF;
  final fgR = (sticker.fgColor >> 16) & 0xFF;
  final fgG = (sticker.fgColor >> 8) & 0xFF;
  final fgB = sticker.fgColor & 0xFF;

  final bgCol = img.ColorRgba8(bgR, bgG, bgB, 255);
  final fgCol = img.ColorRgba8(fgR, fgG, fgB, 255);
  final white8 = img.ColorRgba8(255, 255, 255, 60);

  // Draw shape
  switch (sticker.shape) {
    case 'circle':
      img.fillCircle(canvas, x: 256, y: 256, radius: 230, color: bgCol);
      // Inner highlight
      img.fillCircle(canvas, x: 220, y: 200, radius: 60, color: white8);
      break;
    case 'star':
      // Draw a rounded rectangle with decorative corners as "star-like"
      img.fillRect(canvas,
          x1: 40, y1: 40, x2: 472, y2: 472,
          color: bgCol,
          radius: 60);
      // Corner accents
      img.fillCircle(canvas, x: 60, y: 60, radius: 35, color: bgCol);
      img.fillCircle(canvas, x: 452, y: 60, radius: 35, color: bgCol);
      img.fillCircle(canvas, x: 60, y: 452, radius: 35, color: bgCol);
      img.fillCircle(canvas, x: 452, y: 452, radius: 35, color: bgCol);
      // Sparkle highlight
      img.fillCircle(canvas, x: 200, y: 160, radius: 40, color: white8);
      break;
    case 'speech_bubble':
      img.fillRect(canvas,
          x1: 30, y1: 30, x2: 482, y2: 400,
          color: bgCol,
          radius: 50);
      // Bubble tail
      for (int i = 0; i < 80; i++) {
        final x = 120 + i;
        const y1t = 400;
        final y2t = 400 + (i * 1.2).toInt();
        if (y2t < 500) {
          img.drawLine(canvas, x1: x, y1: y1t, x2: x, y2: y2t, color: bgCol);
        }
      }
      break;
    case 'heart':
      // Approximate heart shape
      img.fillCircle(canvas, x: 190, y: 190, radius: 120, color: bgCol);
      img.fillCircle(canvas, x: 322, y: 190, radius: 120, color: bgCol);
      // Triangle bottom
      for (int y = 200; y < 440; y++) {
        final halfWidth = ((440 - y) * 240 / 240).toInt();
        const cx = 256;
        img.drawLine(canvas,
            x1: cx - halfWidth, y1: y,
            x2: cx + halfWidth, y2: y,
            color: bgCol);
      }
      img.fillCircle(canvas, x: 170, y: 160, radius: 35, color: white8);
      break;
    default: // rounded_rect
      img.fillRect(canvas,
          x1: 30, y1: 60, x2: 482, y2: 452,
          color: bgCol,
          radius: 50);
      img.fillCircle(canvas, x: 180, y: 140, radius: 50, color: white8);
      break;
  }

  // Draw 8px white stroke outline
  // (simplified: draw text with shadow effect for outline)

  // Draw text
  final lines = sticker.text.split('\n');
  final font = img.arial48;
  const lineHeight = 52;
  final totalTextHeight = lines.length * lineHeight;
  var startY = (size - totalTextHeight) ~/ 2;

  for (final line in lines) {
    // Estimate text width (rough: 24px per char)
    final textWidth = line.length * 26;
    final startX = (size - textWidth) ~/ 2;

    // Draw shadow
    img.drawString(canvas, line,
        font: font,
        x: startX + 2, y: startY + 2,
        color: img.ColorRgba8(0, 0, 0, 120));

    // Draw text
    img.drawString(canvas, line,
        font: font,
        x: startX, y: startY,
        color: fgCol);

    startY += lineHeight;
  }

  return canvas;
}

void main() {
  const outputDir = 'assets/seed_stickers';

  final packs = [
    brainrotPack,
    reactionPack,
    aiTechPack,
    wholesomePack,
    dailyLifePack,
  ];

  var totalGenerated = 0;

  for (final pack in packs) {
    print('Generating pack: ${pack.name} (${pack.stickers.length} stickers)');

    for (int i = 0; i < pack.stickers.length; i++) {
      final sticker = pack.stickers[i];
      final image = generateSticker(sticker);
      final pngBytes = img.encodePng(image);

      final fileName = '${pack.prefix}_${i + 1}.png';
      final filePath = '$outputDir/$fileName';
      File(filePath).writeAsBytesSync(pngBytes);
      totalGenerated++;

      if ((i + 1) % 10 == 0) {
        print('  Generated ${i + 1}/${pack.stickers.length}');
      }
    }
    print('  Done: ${pack.stickers.length} stickers');
  }

  print('\nTotal stickers generated: $totalGenerated');
}
