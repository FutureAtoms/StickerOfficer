import 'package:flutter/material.dart';

/// Centralized guardrails for sticker creation.
///
/// Enforces WhatsApp-compatible size, duration, and frame limits.
/// Also provides kid-safe text validation and friendly messaging.
class StickerGuardrails {
  // -- Size limits ---------------------------------------------------------
  static const int maxStaticSizeBytes = 100 * 1024; // 100 KB
  static const int maxAnimatedSizeBytes = 500 * 1024; // 500 KB

  // -- Frame limits --------------------------------------------------------
  static const int minFrames = 2;
  static const int maxFrames = 8;

  // -- FPS / Duration limits -----------------------------------------------
  static const int minFps = 4;
  static const int maxFps = 8;
  static const int minDurationMs = 500; // 0.5 s
  static const int maxDurationMs = 10000; // 10 s

  // -- Canvas size ---------------------------------------------------------
  static const int stickerSize = 512;
  static const int trayIconSize = 96;

  // -- Text limits ---------------------------------------------------------
  static const int maxTextLength = 50;
  static const double minTextSize = 16.0;
  static const double maxTextSize = 64.0;

  // -- Pack limits ---------------------------------------------------------
  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;

  // =========================================================================
  // Animated sticker validation
  // =========================================================================

  /// Returns a list of user-friendly error strings. Empty list = valid.
  static List<String> validateAnimatedSticker({
    required int frameCount,
    required int estimatedSizeBytes,
    required int fps,
    String? overlayText,
  }) {
    final errors = <String>[];

    // Frame count
    if (frameCount < minFrames) {
      errors.add('Add at least $minFrames pictures to make it move!');
    }
    if (frameCount > maxFrames) {
      errors.add('Too many frames! Use $maxFrames or fewer.');
    }

    // FPS
    if (fps < minFps) {
      errors.add('Speed is too slow. Use at least $minFps FPS.');
    }
    if (fps > maxFps) {
      errors.add('Speed is too fast. Use $maxFps FPS or less.');
    }

    // Duration
    if (frameCount >= minFrames) {
      final durationMs = totalDurationMs(frameCount, fps);
      if (durationMs < minDurationMs) {
        errors.add('Animation is too short — add more frames or slow down!');
      }
      if (durationMs > maxDurationMs) {
        errors.add(
          'Animation is too long (${(durationMs / 1000).toStringAsFixed(1)}s). '
          'Remove some frames or speed up!',
        );
      }
    }

    // Size
    if (estimatedSizeBytes > maxAnimatedSizeBytes) {
      errors.add(
        'Sticker is too big (${(estimatedSizeBytes / 1024).toStringAsFixed(0)} KB). '
        'Remove frames or use smaller images!',
      );
    }

    // Text
    if (overlayText != null) {
      errors.addAll(_validateText(overlayText));
    }

    return errors;
  }

  // =========================================================================
  // Static sticker validation
  // =========================================================================

  static List<String> validateStaticSticker({
    required int sizeBytes,
    String? overlayText,
  }) {
    final errors = <String>[];

    if (sizeBytes > maxStaticSizeBytes) {
      errors.add(
        'Sticker is too big (${(sizeBytes / 1024).toStringAsFixed(0)} KB). '
        'Try cropping or using a smaller image!',
      );
    }

    if (overlayText != null) {
      errors.addAll(_validateText(overlayText));
    }

    return errors;
  }

  // =========================================================================
  // Text validation (kid-safe)
  // =========================================================================

  static List<String> _validateText(String text) {
    final errors = <String>[];

    if (text.length > maxTextLength) {
      errors.add(
        'Text is too long! Keep it under $maxTextLength characters.',
      );
    }

    if (!isKidSafeText(text)) {
      errors.add(
        'Oops! Please use friendly words only.',
      );
    }

    return errors;
  }

  /// Basic kid-safe content filter.
  /// Returns true if the text passes the filter.
  static bool isKidSafeText(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return true;

    // Block common inappropriate words (minimal list — extend as needed)
    const blocked = <String>[
      'damn',
      'hell',
      'crap',
      'stupid',
      'idiot',
      'hate',
      'kill',
      'die',
      'suck',
      'dumb',
      'ugly',
      'shut up',
      'loser',
    ];

    for (final word in blocked) {
      // Match whole words using word boundary regex
      final pattern = RegExp(r'\b' + RegExp.escape(word) + r'\b');
      if (pattern.hasMatch(lower)) return false;
    }

    return true;
  }

  /// Cleans text for safe display — trims whitespace, enforces max length.
  static String sanitizeText(String input) {
    var text = input.trim();
    if (text.length > maxTextLength) {
      text = text.substring(0, maxTextLength);
    }
    return text;
  }

  // =========================================================================
  // Duration helpers
  // =========================================================================

  /// Total animation duration in milliseconds.
  static int totalDurationMs(int frameCount, int fps) {
    if (fps <= 0) return 0;
    return ((frameCount / fps) * 1000).round();
  }

  /// Whether the animation duration is within safe bounds.
  static bool isDurationSafe(int frameCount, int fps) {
    final ms = totalDurationMs(frameCount, fps);
    return ms >= minDurationMs && ms <= maxDurationMs;
  }

  /// Human-readable duration string.
  static String durationLabel(int frameCount, int fps) {
    final ms = totalDurationMs(frameCount, fps);
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  // =========================================================================
  // Size helpers
  // =========================================================================

  /// Returns the safety status of the given file size.
  static SizeStatus sizeStatus(int sizeBytes, {bool isAnimated = false}) {
    final maxBytes = isAnimated ? maxAnimatedSizeBytes : maxStaticSizeBytes;
    final warningThreshold = isAnimated ? 400 * 1024 : 80 * 1024;

    if (sizeBytes > maxBytes) return SizeStatus.tooLarge;
    if (sizeBytes > warningThreshold) return SizeStatus.warning;
    return SizeStatus.safe;
  }

  /// User-friendly size label.
  static String sizeLabel(int sizeBytes) {
    final kb = sizeBytes / 1024;
    if (kb < 1) return '< 1 KB';
    return '${kb.toStringAsFixed(0)} KB';
  }

  /// Color for size indicator.
  static Color sizeColor(SizeStatus status) {
    switch (status) {
      case SizeStatus.safe:
        return Colors.green;
      case SizeStatus.warning:
        return Colors.orange;
      case SizeStatus.tooLarge:
        return Colors.red;
    }
  }

  /// Kid-friendly tip based on size status.
  static String sizeTip(SizeStatus status, {bool isAnimated = false}) {
    switch (status) {
      case SizeStatus.safe:
        return 'Perfect size!';
      case SizeStatus.warning:
        return 'Getting big — try simpler images!';
      case SizeStatus.tooLarge:
        if (isAnimated) {
          return 'Too big! Remove some frames or use smaller pictures.';
        }
        return 'Too big! Try cropping or using a smaller image.';
    }
  }
}

/// File size safety status.
enum SizeStatus { safe, warning, tooLarge }

/// Text animation presets for animated stickers.
enum TextAnimation {
  none('No Animation', Icons.text_fields),
  bounce('Bounce', Icons.sports_basketball),
  fadeIn('Fade In', Icons.gradient),
  slideUp('Slide Up', Icons.arrow_upward),
  wave('Wave', Icons.waves),
  grow('Grow', Icons.zoom_in),
  shake('Shake', Icons.vibration);

  final String label;
  final IconData icon;

  const TextAnimation(this.label, this.icon);
}
