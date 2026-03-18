import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppTypography {
  static TextTheme get textTheme => TextTheme(
    displayLarge: GoogleFonts.nunito(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    headlineMedium: GoogleFonts.nunito(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleLarge: GoogleFonts.nunito(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.5,
    ),
    labelLarge: GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    bodySmall: GoogleFonts.nunito(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
  );
}
