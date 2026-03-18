import 'package:flutter/material.dart';

abstract class AppColors {
  // Primary gradient
  static const coral = Color(0xFFFF6B6B);
  static const purple = Color(0xFFA855F7);
  static const primaryGradient = LinearGradient(
    colors: [coral, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Secondary
  static const teal = Color(0xFF06D6A0);
  static const success = Color(0xFF22C55E);

  // WhatsApp green
  static const whatsappGreen = Color(0xFF25D366);

  // Backgrounds
  static const backgroundLight = Color(0xFFFFF8F0);
  static const backgroundDark = Color(0xFF1A1A2E);
  static const cardLight = Colors.white;
  static const cardDark = Color(0xFF2A2A3E);

  // Text
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6B7280);
  static const textOnDark = Color(0xFFF9FAFB);

  // Category pastel colors
  static const pastels = [
    Color(0xFFFFE0E0), // pink
    Color(0xFFE0F0FF), // blue
    Color(0xFFE0FFE0), // green
    Color(0xFFFFF0E0), // orange
    Color(0xFFE8E0FF), // lavender
    Color(0xFFFFE0F5), // magenta
    Color(0xFFE0FFFF), // cyan
    Color(0xFFFFF5E0), // gold
  ];

  // Shadows
  static const shadowLight = Color(0x1A000000);
  static const shadowMedium = Color(0x33000000);
}
