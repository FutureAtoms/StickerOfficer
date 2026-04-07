import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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

  // -- Video-to-sticker limits (do NOT change manual sticker limits above) --
  static const int videoMaxFrames = 75; // 5s x 15fps
  static const int videoMaxFps = 15;
  static const int videoMinFps = 8;
  static const int videoMaxDurationMs = 5000; // 5 seconds
  static const int minGifResolution = 256;
  static const int maxGifResolution = 512;
  static const List<int> qualityFpsStops = [8, 10, 12, 13, 15];
  static const List<int> qualityResStops = [512, 448, 384, 352, 320];
  static const List<int> qualityColorStops = [256, 224, 192, 160, 128];

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
  // Video-sourced sticker validation
  // =========================================================================

  /// Validates a video-sourced animated sticker using video-specific limits.
  static List<String> validateVideoSticker({
    required int frameCount,
    required int fps,
    required int sizeBytes,
    String? text,
  }) {
    final errors = <String>[];

    if (frameCount < minFrames) {
      errors.add('Need at least $minFrames frames!');
    }
    if (frameCount > videoMaxFrames) {
      errors.add('Too many frames! Max is $videoMaxFrames.');
    }

    if (fps < videoMinFps) {
      errors.add('Speed too slow. Use at least $videoMinFps FPS.');
    }
    if (fps > videoMaxFps) {
      errors.add('Speed too fast. Use $videoMaxFps FPS or less.');
    }

    if (sizeBytes > maxAnimatedSizeBytes) {
      errors.add(
        'Sticker is too big (${(sizeBytes / 1024).toStringAsFixed(0)} KB). '
        'Try a shorter clip or move slider toward Crisp!',
      );
    }

    if (text != null) {
      errors.addAll(_validateText(text));
    }

    return errors;
  }

  // =========================================================================
  // Text validation (kid-safe)
  // =========================================================================

  static List<String> _validateText(String text) {
    final errors = <String>[];

    if (text.length > maxTextLength) {
      errors.add('Text is too long! Keep it under $maxTextLength characters.');
    }

    if (!isKidSafeText(text)) {
      errors.add('Oops! Please use friendly words only.');
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

  /// Rough estimate of GIF file size in KB.
  /// Approximate — the auto-retry mechanism is the true safety net.
  static double estimateGifSizeKB({
    required double durationSec,
    required int fps,
    required int resolution,
  }) {
    final frameCount = (durationSec * fps).ceil();
    // ~3 bytes per pixel, GIF compresses roughly 10x for typical video content
    final rawBytesPerFrame = resolution * resolution * 3;
    const compressionRatio = 10.0;
    final totalBytes = (frameCount * rawBytesPerFrame) / compressionRatio;
    return totalBytes / 1024;
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

  // =========================================================================
  // Normalization — best-effort 512x512 PNG
  // =========================================================================

  /// Normalizes any image bytes to a 512x512 PNG.
  ///
  /// Attempts to keep the result under [maxStaticSizeBytes] by quantizing
  /// colors, but returns the PNG as-is if it still exceeds the limit.
  /// WhatsApp export handles final size enforcement via WebP conversion.
  static Uint8List normalizeStaticSticker(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final resized = _resizeAndCenter(decoded, stickerSize);
    final png = Uint8List.fromList(img.encodePng(resized, level: 9));
    if (png.lengthInBytes <= maxStaticSizeBytes) return png;

    // Quantize to reduce size
    final quantized = img.quantize(resized, numberOfColors: 32);
    final quantizedPng = Uint8List.fromList(img.encodePng(quantized, level: 9));

    // Return best-effort — may still be > 100KB for photographic content
    return quantizedPng.lengthInBytes <= maxStaticSizeBytes
        ? quantizedPng
        : png;
  }

  // =========================================================================
  // Compression utilities
  // =========================================================================

  /// Compresses a static sticker to fit within [maxStaticSizeBytes].
  ///
  /// Always outputs 512x512 — never reduces dimensions.
  /// Escalates compression gradually to preserve quality:
  ///   1. PNG with max compression (lossless)
  ///   2. Color quantization (slight quality loss)
  ///   3. JPEG encoding (lossy but keeps 512x512)
  static Future<Uint8List> compressStaticSticker(Uint8List pngBytes) async {
    if (pngBytes.lengthInBytes <= maxStaticSizeBytes) return pngBytes;

    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;

    // Always resize to 512x512
    final resized = _resizeAndCenter(decoded, stickerSize);

    // Strategy 1: PNG with max compression — lossless
    final pngMax = Uint8List.fromList(img.encodePng(resized, level: 9));
    if (pngMax.lengthInBytes <= maxStaticSizeBytes) return pngMax;

    // Strategy 2: Quantize colors — slight quality loss, keeps 512x512
    for (final colors in [256, 192, 128, 96, 64]) {
      final quantized = img.quantize(resized, numberOfColors: colors);
      final encoded = Uint8List.fromList(img.encodePng(quantized, level: 9));
      if (encoded.lengthInBytes <= maxStaticSizeBytes) return encoded;
    }

    // Strategy 3: JPEG at good quality — visually near-identical
    for (var q = 90; q >= 30; q -= 10) {
      final jpegBytes = img.encodeJpg(resized, quality: q);
      if (jpegBytes.length <= maxStaticSizeBytes) {
        return Uint8List.fromList(jpegBytes);
      }
    }

    // Fallback: heavy quantize + max compression
    final quantized = img.quantize(resized, numberOfColors: 32);
    return Uint8List.fromList(img.encodePng(quantized, level: 9));
  }

  /// Compresses animated sticker frames to fit within [maxAnimatedSizeBytes].
  /// Reduces frame dimensions and PNG compression until the total estimated
  /// GIF size fits. Returns the list of compressed frame bytes.
  static Future<List<Uint8List>> compressAnimatedFrames(
    List<Uint8List> frames,
  ) async {
    // Estimate current size
    int estimatedSize = _estimateGifSize(frames);
    if (estimatedSize <= maxAnimatedSizeBytes) return frames;

    // Strategy: resize all frames to smaller dimensions
    var targetSize = stickerSize;
    var compressed = frames;

    while (targetSize >= 128 &&
        _estimateGifSize(compressed) > maxAnimatedSizeBytes) {
      targetSize = (targetSize * 0.8).floor();
      compressed = [];
      for (final frameBytes in frames) {
        final decoded = img.decodeImage(frameBytes);
        if (decoded == null) {
          compressed.add(frameBytes);
          continue;
        }
        final resized = _resizeAndCenter(decoded, targetSize);
        compressed.add(Uint8List.fromList(img.encodePng(resized, level: 6)));
      }
    }

    return compressed;
  }

  static int _estimateGifSize(List<Uint8List> frames) {
    final rawSum = frames.fold<int>(0, (sum, f) => sum + f.lengthInBytes);
    return (rawSum * 0.6).round();
  }

  /// Resizes and centers an image on a transparent canvas.
  static img.Image _resizeAndCenter(img.Image source, int size) {
    final scale =
        size / (source.width > source.height ? source.width : source.height);
    final newWidth = (source.width * scale).round().clamp(1, size);
    final newHeight = (source.height * scale).round().clamp(1, size);

    final resized = img.copyResize(
      source,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    final offsetX = (size - newWidth) ~/ 2;
    final offsetY = (size - newHeight) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    return canvas;
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

/// Computes the text position and alpha for a given animation at a specific
/// frame index within a multi-frame animated sticker.
///
/// Returns a [TextAnimationTransform] with x/y offsets relative to the base
/// position, a scale factor, and an alpha (opacity) value 0–255.
///
/// All transforms are designed to loop smoothly across the frame sequence.
class TextAnimationTransform {
  /// X offset from the base text position.
  final int dx;

  /// Y offset from the base text position.
  final int dy;

  /// Scale factor (1.0 = normal size). Used by [TextAnimation.grow].
  final double scale;

  /// Alpha / opacity 0–255. Used by [TextAnimation.fadeIn].
  final int alpha;

  const TextAnimationTransform({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1.0,
    this.alpha = 230,
  });

  @override
  String toString() =>
      'TextAnimationTransform(dx: $dx, dy: $dy, scale: $scale, alpha: $alpha)';
}

/// Computes the [TextAnimationTransform] for a given [animation] type
/// at frame [frameIndex] out of [totalFrames].
///
/// Pure function — no side effects, fully testable.
TextAnimationTransform computeTextTransform({
  required TextAnimation animation,
  required int frameIndex,
  required int totalFrames,
}) {
  if (totalFrames <= 0) {
    return const TextAnimationTransform();
  }

  // Normalized progress 0.0 → 1.0 across all frames
  final t = totalFrames == 1 ? 0.0 : frameIndex / (totalFrames - 1);

  switch (animation) {
    case TextAnimation.none:
      return const TextAnimationTransform();

    case TextAnimation.bounce:
      // Bounce: y oscillates using a sine curve, amplitude 20px
      final bounceY = (-20 * _sin(t * 2 * 3.14159)).round();
      return TextAnimationTransform(dy: bounceY);

    case TextAnimation.fadeIn:
      // Fade from 0 to full alpha across all frames
      final alpha = (30 + (200 * t)).round().clamp(0, 230);
      return TextAnimationTransform(alpha: alpha);

    case TextAnimation.slideUp:
      // Slide from 40px below to base position
      final slideY = (40 * (1.0 - t)).round();
      final alpha = (50 + (180 * t)).round().clamp(0, 230);
      return TextAnimationTransform(dy: slideY, alpha: alpha);

    case TextAnimation.wave:
      // Horizontal wave: x oscillates ±15px using sine
      final waveX = (15 * _sin(t * 2 * 3.14159)).round();
      final waveY = (-8 * _sin(t * 4 * 3.14159)).round();
      return TextAnimationTransform(dx: waveX, dy: waveY);

    case TextAnimation.grow:
      // Scale from 0.5 to 1.0 across frames
      final scale = 0.5 + 0.5 * t;
      return TextAnimationTransform(scale: scale);

    case TextAnimation.shake:
      // Quick horizontal jitter, alternating ±10px per frame
      final shakeX = (frameIndex % 2 == 0) ? 10 : -10;
      return TextAnimationTransform(dx: shakeX);
  }
}

/// Simple sine approximation using dart:math would require an import.
/// We use a Taylor-series-based sine for small pure-Dart usage.
double _sin(double x) {
  // Normalize x to [-pi, pi]
  const pi = 3.14159265358979;
  x = x % (2 * pi);
  if (x > pi) x -= 2 * pi;
  if (x < -pi) x += 2 * pi;
  // Taylor series: sin(x) ≈ x - x³/6 + x⁵/120 - x⁷/5040
  final x2 = x * x;
  final x3 = x2 * x;
  final x5 = x3 * x2;
  final x7 = x5 * x2;
  return x - x3 / 6.0 + x5 / 120.0 - x7 / 5040.0;
}
