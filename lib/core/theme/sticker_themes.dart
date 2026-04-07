import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_typography.dart';

// =============================================================================
// Theme type enum
// =============================================================================

enum StickerThemeType {
  bubblegum,
  clay,
  frostedGlass,
  candyPop,
  oceanCalm,
  sunsetGlow,
}

// =============================================================================
// Theme data model
// =============================================================================

class StickerThemeData {
  final String name;
  final StickerThemeType type;
  final Color seedColor;
  final Color accent;
  final Color background;
  final Color cardColor;
  final Color textPrimary;
  final Color textSecondary;
  final LinearGradient gradient;
  final double cardRadius;
  final double buttonRadius;
  final double cardElevation;
  final Color cardShadowColor;
  final bool isDark;

  const StickerThemeData({
    required this.name,
    required this.type,
    required this.seedColor,
    required this.accent,
    required this.background,
    required this.cardColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.gradient,
    required this.cardRadius,
    required this.buttonRadius,
    required this.cardElevation,
    required this.cardShadowColor,
    this.isDark = false,
  });

  /// Generates a complete [ThemeData] from this sticker theme definition.
  ThemeData themeData() {
    final brightness = isDark ? Brightness.dark : Brightness.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      primary: seedColor,
      secondary: accent,
      surface: cardColor,
      brightness: brightness,
    );

    final textTheme = AppTypography.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: cardElevation,
        shadowColor: cardShadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: AppTypography.textTheme.labelLarge,
          elevation: 2,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? cardColor : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? cardColor : Colors.white,
        selectedItemColor: seedColor,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: seedColor.withValues(alpha: isDark ? 0.2 : 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? cardColor : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cardRadius + 4),
          ),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
    );
  }
}

// =============================================================================
// Pre-defined themes
// =============================================================================

class StickerThemes {
  StickerThemes._();

  // -------------------------------------------------------------------------
  // 1. Bubblegum (default) — warm, playful, current app identity
  // -------------------------------------------------------------------------
  static const bubblegum = StickerThemeData(
    name: 'Bubblegum',
    type: StickerThemeType.bubblegum,
    seedColor: Color(0xFFFF6B6B),
    accent: Color(0xFFA855F7),
    background: Color(0xFFFFF8F0),
    cardColor: Colors.white,
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF6B7280),
    gradient: LinearGradient(
      colors: [Color(0xFFFF6B6B), Color(0xFFA855F7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 28,
    cardElevation: 2,
    cardShadowColor: Color(0x1A000000),
  );

  // -------------------------------------------------------------------------
  // 2. Clay — soft pastel pink/beige claymorphism
  // -------------------------------------------------------------------------
  static const clay = StickerThemeData(
    name: 'Clay',
    type: StickerThemeType.clay,
    seedColor: Color(0xFFE8A0BF),
    accent: Color(0xFFB4D4A6),
    background: Color(0xFFF5EDE3),
    cardColor: Color(0xFFF0E6DA),
    textPrimary: Color(0xFF4A3728),
    textSecondary: Color(0xFF8B7355),
    gradient: LinearGradient(
      colors: [Color(0xFFE8A0BF), Color(0xFFD4B5A0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 24,
    buttonRadius: 30,
    cardElevation: 0, // clay uses custom box shadows instead
    cardShadowColor: Color(0x40D4B5A0),
  );

  // -------------------------------------------------------------------------
  // 3. Frosted Glass — translucent, cool blue/purple, subtle blur
  // -------------------------------------------------------------------------
  static const frostedGlass = StickerThemeData(
    name: 'Frosted Glass',
    type: StickerThemeType.frostedGlass,
    seedColor: Color(0xFF7C8CF8),
    accent: Color(0xFF64D2FF),
    background: Color(0xFFE8ECF4),
    cardColor: Color(0xCCFFFFFF), // semi-transparent white
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF64748B),
    gradient: LinearGradient(
      colors: [Color(0xFF7C8CF8), Color(0xFF64D2FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 22,
    buttonRadius: 28,
    cardElevation: 0, // glass uses backdrop filter instead
    cardShadowColor: Color(0x207C8CF8),
  );

  // -------------------------------------------------------------------------
  // 4. Candy Pop — bright saturated candy colors
  // -------------------------------------------------------------------------
  static const candyPop = StickerThemeData(
    name: 'Candy Pop',
    type: StickerThemeType.candyPop,
    seedColor: Color(0xFFFF2D78),
    accent: Color(0xFF00E5FF),
    background: Color(0xFFFFF0F5),
    cardColor: Colors.white,
    textPrimary: Color(0xFF1A0A2E),
    textSecondary: Color(0xFF7B5EA7),
    gradient: LinearGradient(
      colors: [Color(0xFFFF2D78), Color(0xFF00E5FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 22,
    buttonRadius: 30,
    cardElevation: 3,
    cardShadowColor: Color(0x30FF2D78),
  );

  // -------------------------------------------------------------------------
  // 5. Ocean Calm — deep teal/navy, calming blues
  // -------------------------------------------------------------------------
  static const oceanCalm = StickerThemeData(
    name: 'Ocean Calm',
    type: StickerThemeType.oceanCalm,
    seedColor: Color(0xFF0EA5E9),
    accent: Color(0xFF06D6A0),
    background: Color(0xFF0F172A),
    cardColor: Color(0xFF1E293B),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    gradient: LinearGradient(
      colors: [Color(0xFF0EA5E9), Color(0xFF06D6A0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 28,
    cardElevation: 4,
    cardShadowColor: Color(0x400EA5E9),
    isDark: true,
  );

  // -------------------------------------------------------------------------
  // 6. Sunset Glow — warm amber/orange/rose, golden hour
  // -------------------------------------------------------------------------
  static const sunsetGlow = StickerThemeData(
    name: 'Sunset Glow',
    type: StickerThemeType.sunsetGlow,
    seedColor: Color(0xFFF59E0B),
    accent: Color(0xFFF472B6),
    background: Color(0xFFFFFBEB),
    cardColor: Color(0xFFFFF7ED),
    textPrimary: Color(0xFF451A03),
    textSecondary: Color(0xFF92400E),
    gradient: LinearGradient(
      colors: [Color(0xFFF59E0B), Color(0xFFF472B6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 24,
    buttonRadius: 30,
    cardElevation: 2,
    cardShadowColor: Color(0x30F59E0B),
  );

  /// All available themes in display order.
  static const List<StickerThemeData> all = [
    bubblegum,
    clay,
    frostedGlass,
    candyPop,
    oceanCalm,
    sunsetGlow,
  ];

  /// Look up a theme by its [StickerThemeType].
  static StickerThemeData fromType(StickerThemeType type) {
    return all.firstWhere((t) => t.type == type);
  }

  /// Look up a theme by its persisted string key.
  static StickerThemeData fromKey(String key) {
    final type = StickerThemeType.values.firstWhere(
      (t) => t.name == key,
      orElse: () => StickerThemeType.bubblegum,
    );
    return fromType(type);
  }
}
