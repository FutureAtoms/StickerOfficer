# Video-to-Sticker Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the choppy video_thumbnail-based pipeline with an FFmpeg-powered Instagram-style trim-and-convert flow that produces smooth, vibrant animated stickers within WhatsApp's 500KB limit.

**Architecture:** Two-screen flow preserved (VideoToStickerScreen -> AnimatedStickerScreen). FFmpeg handles trimming, palette generation, and GIF encoding via a two-pass pipeline. Video-specific guardrail constants keep the manual sticker flow untouched.

**Tech Stack:** Flutter, ffmpeg_kit_flutter_min_gpl, image package (existing), Riverpod, GoRouter

---

### Task 1: Add FFmpeg Dependency and Remove video_thumbnail

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Update pubspec.yaml**

In `pubspec.yaml`, under `# Image/Video` section:

Remove:
```yaml
  video_thumbnail: ^0.5.3
```

Add:
```yaml
  ffmpeg_kit_flutter_min_gpl: ^6.0.3
```

- [ ] **Step 2: Run pub get**

Run: `cd /Users/abhilashchadhar/uncloud/StickOfficer/StickerOfficer && flutter pub get`
Expected: Dependencies resolve successfully, no errors.

- [ ] **Step 3: Verify build compiles**

Run: `cd /Users/abhilashchadhar/uncloud/StickOfficer/StickerOfficer && flutter analyze`
Expected: May show warnings about unused video_thumbnail imports in video_to_sticker_screen.dart (that's fine — we'll rewrite it in Task 4).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add ffmpeg_kit_flutter_min_gpl, remove video_thumbnail"
```

- [ ] **Step 5: VALIDATE on emulator**

Run the app on the emulator. Navigate around. Confirm it launches and existing screens work.

```
/ralph-loop "Run the app on emulator with 'flutter run'. Once it launches, navigate to the home screen, explore screen, my packs, and profile to confirm nothing is broken. Then output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

---

### Task 2: Add Video-Specific Guardrail Constants

**Files:**
- Modify: `lib/core/utils/sticker_guardrails.dart`
- Test: `test/unit/sticker_guardrails_test.dart` (add new tests, don't change existing)

- [ ] **Step 1: Write failing tests for new constants and functions**

Add to bottom of the existing test file `test/unit/sticker_guardrails_test.dart`:

```dart
  // =========================================================================
  // Video-specific guardrails
  // =========================================================================

  group('Video-specific constants', () {
    test('videoMaxFrames is 75 (5s x 15fps)', () {
      expect(StickerGuardrails.videoMaxFrames, 75);
    });

    test('videoMaxFps is 15', () {
      expect(StickerGuardrails.videoMaxFps, 15);
    });

    test('videoMinFps is 8', () {
      expect(StickerGuardrails.videoMinFps, 8);
    });

    test('videoMaxDurationMs is 5000', () {
      expect(StickerGuardrails.videoMaxDurationMs, 5000);
    });

    test('qualityFpsStops has 5 stops', () {
      expect(StickerGuardrails.qualityFpsStops.length, 5);
      expect(StickerGuardrails.qualityFpsStops, [8, 10, 12, 13, 15]);
    });

    test('qualityResStops has 5 stops matching FPS stops', () {
      expect(StickerGuardrails.qualityResStops.length, 5);
      expect(StickerGuardrails.qualityResStops, [512, 448, 384, 352, 320]);
    });

    test('qualityColorStops has 5 stops', () {
      expect(StickerGuardrails.qualityColorStops.length, 5);
      expect(StickerGuardrails.qualityColorStops, [256, 224, 192, 160, 128]);
    });

    test('global maxFrames and maxFps unchanged', () {
      // CRITICAL: these must NOT change, they protect the manual sticker flow
      expect(StickerGuardrails.maxFrames, 8);
      expect(StickerGuardrails.maxFps, 8);
    });
  });

  group('validateVideoSticker', () {
    test('valid video sticker passes', () {
      final errors = StickerGuardrails.validateVideoSticker(
        frameCount: 60,
        fps: 12,
        sizeBytes: 400 * 1024,
      );
      expect(errors, isEmpty);
    });

    test('too many frames fails', () {
      final errors = StickerGuardrails.validateVideoSticker(
        frameCount: 80,
        fps: 12,
        sizeBytes: 400 * 1024,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('75'));
    });

    test('fps too high fails', () {
      final errors = StickerGuardrails.validateVideoSticker(
        frameCount: 30,
        fps: 20,
        sizeBytes: 400 * 1024,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('15'));
    });

    test('fps too low fails', () {
      final errors = StickerGuardrails.validateVideoSticker(
        frameCount: 30,
        fps: 3,
        sizeBytes: 400 * 1024,
      );
      expect(errors, isNotEmpty);
    });

    test('size over 500KB fails', () {
      final errors = StickerGuardrails.validateVideoSticker(
        frameCount: 30,
        fps: 12,
        sizeBytes: 600 * 1024,
      );
      expect(errors, isNotEmpty);
      expect(errors.first, contains('big'));
    });
  });

  group('estimateGifSizeKB', () {
    test('returns positive value', () {
      final size = StickerGuardrails.estimateGifSizeKB(
        durationSec: 3.0,
        fps: 12,
        resolution: 384,
      );
      expect(size, greaterThan(0));
    });

    test('higher fps = larger estimate', () {
      final lowFps = StickerGuardrails.estimateGifSizeKB(
        durationSec: 3.0,
        fps: 8,
        resolution: 384,
      );
      final highFps = StickerGuardrails.estimateGifSizeKB(
        durationSec: 3.0,
        fps: 15,
        resolution: 384,
      );
      expect(highFps, greaterThan(lowFps));
    });

    test('higher resolution = larger estimate', () {
      final lowRes = StickerGuardrails.estimateGifSizeKB(
        durationSec: 3.0,
        fps: 12,
        resolution: 320,
      );
      final highRes = StickerGuardrails.estimateGifSizeKB(
        durationSec: 3.0,
        fps: 12,
        resolution: 512,
      );
      expect(highRes, greaterThan(lowRes));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/sticker_guardrails_test.dart`
Expected: New tests FAIL (constants/functions don't exist yet). Existing tests still PASS.

- [ ] **Step 3: Implement video-specific constants and functions**

In `lib/core/utils/sticker_guardrails.dart`, add after the `maxStickersPerPack` line (line 36):

```dart
  // -- Video-to-sticker limits (do NOT change manual sticker limits above) --
  static const int videoMaxFrames = 75;  // 5s x 15fps
  static const int videoMaxFps = 15;
  static const int videoMinFps = 8;
  static const int videoMaxDurationMs = 5000; // 5 seconds
  static const int minGifResolution = 256;
  static const int maxGifResolution = 512;
  static const List<int> qualityFpsStops = [8, 10, 12, 13, 15];
  static const List<int> qualityResStops = [512, 448, 384, 352, 320];
  static const List<int> qualityColorStops = [256, 224, 192, 160, 128];
```

Add the `validateVideoSticker` function after `validateStaticSticker`:

```dart
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
```

Add the `estimateGifSizeKB` function in the size helpers section:

```dart
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
```

- [ ] **Step 4: Run all tests**

Run: `flutter test test/unit/sticker_guardrails_test.dart`
Expected: ALL tests PASS (old + new).

- [ ] **Step 5: Run full test suite for regression check**

Run: `flutter test`
Expected: All existing tests pass. No regressions.

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/sticker_guardrails.dart test/unit/sticker_guardrails_test.dart
git commit -m "feat: add video-specific guardrail constants and validation"
```

---

### Task 3: Update Route Handler for Backward Compatibility

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/editor/presentation/animated_sticker_screen.dart` (constructor only)

- [ ] **Step 1: Add new constructor parameters to AnimatedStickerScreen**

In `lib/features/editor/presentation/animated_sticker_screen.dart`, update the constructor at lines 29-33:

Change:
```dart
class AnimatedStickerScreen extends ConsumerStatefulWidget {
  /// Optional list of file paths to pre-load as frames (e.g. from video extraction).
  final List<String>? initialFramePaths;

  const AnimatedStickerScreen({super.key, this.initialFramePaths});
```

To:
```dart
class AnimatedStickerScreen extends ConsumerStatefulWidget {
  /// Optional list of file paths to pre-load as frames (e.g. from video extraction).
  final List<String>? initialFramePaths;

  /// Path to an FFmpeg-generated GIF (video-to-sticker flow). If set, this GIF
  /// is used directly on export when the user makes no edits.
  final String? ffmpegGifPath;

  /// Initial FPS from video conversion (video-to-sticker flow).
  final int? initialFps;

  const AnimatedStickerScreen({
    super.key,
    this.initialFramePaths,
    this.ffmpegGifPath,
    this.initialFps,
  });
```

- [ ] **Step 2: Update route handler in app_router.dart**

In `lib/core/router/app_router.dart`, replace lines 125-131:

Change:
```dart
      GoRoute(
        path: '/animated-editor',
        builder: (context, state) {
          final initialFrames = state.extra as List<String>?;
          return AnimatedStickerScreen(initialFramePaths: initialFrames);
        },
      ),
```

To:
```dart
      GoRoute(
        path: '/animated-editor',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return AnimatedStickerScreen(
              initialFramePaths: extra['frames'] as List<String>?,
              ffmpegGifPath: extra['gifPath'] as String?,
              initialFps: extra['fps'] as int?,
            );
          }
          return AnimatedStickerScreen(
            initialFramePaths: extra as List<String>?,
          );
        },
      ),
```

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: All tests pass. The constructor change is backward compatible (new params are optional).

- [ ] **Step 4: VALIDATE on emulator**

Run: `flutter run`
Navigate to animated editor from main shell (which passes null extra). Confirm it still works.

```
/ralph-loop "Run the app on emulator. Navigate to Create > Animated Sticker. Verify the animated sticker screen opens correctly with empty state. Try adding an image. Verify it works. Then output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/editor/presentation/animated_sticker_screen.dart
git commit -m "feat: update route handler and constructor for video-sourced stickers"
```

---

### Task 4: Build the Video Trim Scrubber Widget

**Files:**
- Create: `lib/core/widgets/video_trim_scrubber.dart`

- [ ] **Step 1: Create the widget**

Create `lib/core/widgets/video_trim_scrubber.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// Instagram-style video trim scrubber with thumbnail strip and draggable handles.
class VideoTrimScrubber extends StatefulWidget {
  /// List of thumbnail image bytes to display in the strip.
  final List<Uint8List> thumbnails;

  /// Total video duration in milliseconds.
  final int videoDurationMs;

  /// Max allowed selection duration in milliseconds.
  final int maxSelectionMs;

  /// Min allowed selection duration in milliseconds.
  final int minSelectionMs;

  /// Current selection start (0.0 - 1.0).
  final double selectionStart;

  /// Current selection end (0.0 - 1.0).
  final double selectionEnd;

  /// Current playback position (0.0 - 1.0).
  final double playbackPosition;

  /// Called when user changes the selection range.
  final ValueChanged<RangeValues> onSelectionChanged;

  const VideoTrimScrubber({
    super.key,
    required this.thumbnails,
    required this.videoDurationMs,
    required this.maxSelectionMs,
    this.minSelectionMs = 500,
    required this.selectionStart,
    required this.selectionEnd,
    this.playbackPosition = 0.0,
    required this.onSelectionChanged,
  });

  @override
  State<VideoTrimScrubber> createState() => _VideoTrimScrubberState();
}

class _VideoTrimScrubberState extends State<VideoTrimScrubber> {
  static const double _handleWidth = 16.0;
  static const double _thumbHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    if (widget.thumbnails.isEmpty) {
      return SizedBox(
        height: _thumbHeight + 24,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: _thumbHeight + 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth - _handleWidth * 2;
          final thumbWidth = totalWidth / widget.thumbnails.length;

          return Stack(
            children: [
              // Thumbnail strip
              Positioned(
                left: _handleWidth,
                right: _handleWidth,
                top: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: _thumbHeight,
                    child: Row(
                      children: widget.thumbnails.map((bytes) {
                        return SizedBox(
                          width: thumbWidth,
                          height: _thumbHeight,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // Dim overlay - left of selection
              Positioned(
                left: _handleWidth,
                top: 12,
                width: totalWidth * widget.selectionStart,
                height: _thumbHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              ),

              // Dim overlay - right of selection
              Positioned(
                right: _handleWidth,
                top: 12,
                width: totalWidth * (1.0 - widget.selectionEnd),
                height: _thumbHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(8),
                    ),
                  ),
                ),
              ),

              // Selection border
              Positioned(
                left: _handleWidth + totalWidth * widget.selectionStart,
                top: 12,
                width: totalWidth * (widget.selectionEnd - widget.selectionStart),
                height: _thumbHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.coral, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // Playback indicator
              Positioned(
                left: _handleWidth + totalWidth * widget.playbackPosition - 1,
                top: 10,
                child: Container(
                  width: 2,
                  height: _thumbHeight + 4,
                  color: Colors.white,
                ),
              ),

              // Left handle
              Positioned(
                left: _handleWidth + totalWidth * widget.selectionStart - _handleWidth / 2,
                top: 12,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _onLeftDrag(details, totalWidth);
                  },
                  child: _buildHandle(isLeft: true),
                ),
              ),

              // Right handle
              Positioned(
                left: _handleWidth + totalWidth * widget.selectionEnd - _handleWidth / 2,
                top: 12,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _onRightDrag(details, totalWidth);
                  },
                  child: _buildHandle(isLeft: false),
                ),
              ),

              // Duration label
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  child: _buildDurationLabel(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHandle({required bool isLeft}) {
    return Container(
      width: _handleWidth,
      height: _thumbHeight,
      decoration: BoxDecoration(
        color: AppColors.coral,
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? const Radius.circular(6) : Radius.zero,
          right: isLeft ? Radius.zero : const Radius.circular(6),
        ),
      ),
      child: const Center(
        child: Icon(Icons.drag_indicator, size: 12, color: Colors.white),
      ),
    );
  }

  Widget _buildDurationLabel() {
    final durationMs = ((widget.selectionEnd - widget.selectionStart) *
            widget.videoDurationMs)
        .round();
    final seconds = durationMs / 1000;
    final isTooShort = durationMs < widget.minSelectionMs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isTooShort
            ? AppColors.coral.withValues(alpha: 0.15)
            : AppColors.purple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isTooShort
            ? 'Too short!'
            : '${seconds.toStringAsFixed(1)}s selected',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isTooShort ? AppColors.coral : AppColors.purple,
        ),
      ),
    );
  }

  void _onLeftDrag(DragUpdateDetails details, double totalWidth) {
    HapticFeedback.selectionClick();
    final delta = details.delta.dx / totalWidth;
    var newStart = (widget.selectionStart + delta).clamp(0.0, 1.0);

    // Enforce min selection
    final minFraction = widget.minSelectionMs / widget.videoDurationMs;
    if (widget.selectionEnd - newStart < minFraction) {
      newStart = widget.selectionEnd - minFraction;
    }

    // Enforce max selection
    final maxFraction = widget.maxSelectionMs / widget.videoDurationMs;
    if (widget.selectionEnd - newStart > maxFraction) {
      newStart = widget.selectionEnd - maxFraction;
    }

    widget.onSelectionChanged(RangeValues(newStart, widget.selectionEnd));
  }

  void _onRightDrag(DragUpdateDetails details, double totalWidth) {
    HapticFeedback.selectionClick();
    final delta = details.delta.dx / totalWidth;
    var newEnd = (widget.selectionEnd + delta).clamp(0.0, 1.0);

    // Enforce min selection
    final minFraction = widget.minSelectionMs / widget.videoDurationMs;
    if (newEnd - widget.selectionStart < minFraction) {
      newEnd = widget.selectionStart + minFraction;
    }

    // Enforce max selection
    final maxFraction = widget.maxSelectionMs / widget.videoDurationMs;
    if (newEnd - widget.selectionStart > maxFraction) {
      newEnd = widget.selectionStart + maxFraction;
    }

    widget.onSelectionChanged(RangeValues(widget.selectionStart, newEnd));
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/widgets/video_trim_scrubber.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/core/widgets/video_trim_scrubber.dart
git commit -m "feat: add Instagram-style VideoTrimScrubber widget"
```

---

### Task 5: Rewrite VideoToStickerScreen with FFmpeg Pipeline

**Files:**
- Modify: `lib/features/editor/presentation/video_to_sticker_screen.dart` (full rewrite)

This is the biggest task. The new screen has:
1. Video picker
2. FFmpeg thumbnail strip generation
3. Instagram scrubber (using VideoTrimScrubber widget)
4. Quality vs. Smoothness slider
5. Real-time size estimation
6. FFmpeg two-pass GIF conversion
7. Cancel button
8. Handoff to animated editor via map

- [ ] **Step 1: Rewrite the screen**

Replace entire content of `lib/features/editor/presentation/video_to_sticker_screen.dart` with:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../core/widgets/video_trim_scrubber.dart';

/// Max video duration allowed for sticker creation (seconds).
const _kMaxClipDurationMs = StickerGuardrails.videoMaxDurationMs;

class VideoToStickerScreen extends ConsumerStatefulWidget {
  const VideoToStickerScreen({super.key});

  @override
  ConsumerState<VideoToStickerScreen> createState() =>
      _VideoToStickerScreenState();
}

class _VideoToStickerScreenState extends ConsumerState<VideoToStickerScreen> {
  final ImagePicker _picker = ImagePicker();

  VideoPlayerController? _videoController;
  String? _videoPath;
  bool _isLoading = false;

  // Trim range (0.0 - 1.0)
  double _trimStart = 0.0;
  double _trimEnd = 1.0;

  // Thumbnail strip for scrubber
  final List<Uint8List> _thumbnails = [];
  bool _isGeneratingThumbnails = false;

  // Quality slider (0-4 index into StickerGuardrails.qualityFpsStops)
  int _qualityIndex = 2; // Default: Balanced

  // Conversion state
  bool _isConverting = false;
  String _conversionStatus = '';
  bool _cancelRequested = false;

  // Temp directory for this session
  Directory? _tempDir;

  @override
  void dispose() {
    _videoController?.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Quality slider helpers
  // ---------------------------------------------------------------------------

  int get _fps => StickerGuardrails.qualityFpsStops[_qualityIndex];
  int get _resolution => StickerGuardrails.qualityResStops[_qualityIndex];
  int get _maxColors => StickerGuardrails.qualityColorStops[_qualityIndex];

  String get _qualityLabel {
    const labels = ['Crispest', 'Crisp', 'Balanced', 'Smooth', 'Smoothest'];
    return labels[_qualityIndex];
  }

  double get _clipDurationSec {
    if (_videoController == null) return 0.0;
    final totalMs = _videoController!.value.duration.inMilliseconds;
    return ((totalMs * (_trimEnd - _trimStart)) / 1000.0);
  }

  double get _estimatedSizeKB {
    if (_videoController == null) return 0.0;
    return StickerGuardrails.estimateGifSizeKB(
      durationSec: _clipDurationSec,
      fps: _fps,
      resolution: _resolution,
    );
  }

  // ---------------------------------------------------------------------------
  // Video picking
  // ---------------------------------------------------------------------------

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;

      setState(() {
        _isLoading = true;
        _thumbnails.clear();
      });

      final controller = VideoPlayerController.file(File(video.path));
      await controller.initialize();

      final durationMs = controller.value.duration.inMilliseconds;

      // Set initial trim to first 5s or full video if shorter
      double trimEnd = 1.0;
      if (durationMs > _kMaxClipDurationMs) {
        trimEnd = _kMaxClipDurationMs / durationMs;
      }

      _videoController?.dispose();
      setState(() {
        _videoController = controller;
        _videoPath = video.path;
        _trimStart = 0.0;
        _trimEnd = trimEnd;
        _isLoading = false;
      });

      // Generate thumbnails for scrubber
      _generateThumbnails();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Couldn't load video — try another!", AppColors.coral);
    }
  }

  // ---------------------------------------------------------------------------
  // Thumbnail generation via FFmpeg
  // ---------------------------------------------------------------------------

  Future<void> _generateThumbnails() async {
    if (_videoPath == null || _videoController == null) return;

    setState(() => _isGeneratingThumbnails = true);

    try {
      _tempDir = await getTemporaryDirectory();
      final thumbDir = Directory('${_tempDir!.path}/vtrim_${DateTime.now().millisecondsSinceEpoch}');
      await thumbDir.create(recursive: true);

      final durationSec = _videoController!.value.duration.inSeconds;
      // Generate ~2 thumbnails per second, max 60
      final count = (durationSec * 2).clamp(4, 60);

      final command =
          '-i "$_videoPath" -vf "fps=${count / durationSec}:round=near,scale=80:-1" '
          '-frames:v $count "${thumbDir.path}/thumb_%04d.png"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final thumbFiles = thumbDir.listSync()
          ..sort((a, b) => a.path.compareTo(b.path));

        final thumbBytes = <Uint8List>[];
        for (final file in thumbFiles) {
          if (file is File && file.path.endsWith('.png')) {
            thumbBytes.add(await file.readAsBytes());
          }
        }

        if (mounted) {
          setState(() {
            _thumbnails.clear();
            _thumbnails.addAll(thumbBytes);
          });
        }
      }
    } catch (e) {
      // Thumbnails are non-critical; scrubber works without them
    } finally {
      if (mounted) setState(() => _isGeneratingThumbnails = false);
    }
  }

  // ---------------------------------------------------------------------------
  // FFmpeg two-pass GIF conversion
  // ---------------------------------------------------------------------------

  Future<void> _convertToGif() async {
    if (_videoPath == null || _videoController == null) return;

    final totalMs = _videoController!.value.duration.inMilliseconds;
    final startSec = (totalMs * _trimStart) / 1000.0;
    final durationSec = _clipDurationSec;

    if (durationSec < 0.5) {
      _showSnackBar('Clip is too short! Select at least 0.5 seconds.', AppColors.coral);
      return;
    }

    setState(() {
      _isConverting = true;
      _cancelRequested = false;
      _conversionStatus = 'Generating color palette...';
    });

    try {
      final workDir = Directory(
        '${_tempDir?.path ?? (await getTemporaryDirectory()).path}'
        '/vconvert_${DateTime.now().millisecondsSinceEpoch}',
      );
      await workDir.create(recursive: true);

      // Try conversion at current quality, step down if too large
      int qualityIdx = _qualityIndex;
      String? gifPath;

      for (int attempt = 0; attempt < 3; attempt++) {
        if (_cancelRequested) break;

        final fps = StickerGuardrails.qualityFpsStops[qualityIdx];
        final res = StickerGuardrails.qualityResStops[qualityIdx];
        final colors = StickerGuardrails.qualityColorStops[qualityIdx];

        final palettePath = '${workDir.path}/palette_$attempt.png';
        final outputPath = '${workDir.path}/sticker_$attempt.gif';

        // Pass 1: Generate palette
        if (mounted) setState(() => _conversionStatus = 'Generating color palette...');

        final scaleFilter =
            'fps=$fps,scale=$res:$res:force_original_aspect_ratio=decrease,'
            'pad=$res:$res:(ow-iw)/2:(oh-ih)/2:color=0x00000000';

        final paletteCmd =
            '-ss $startSec -t $durationSec -i "$_videoPath" '
            '-vf "$scaleFilter,palettegen=max_colors=$colors:reserve_transparent=1" '
            '-y "$palettePath"';

        final paletteSession = await FFmpegKit.execute(paletteCmd);
        if (_cancelRequested) break;

        final paletteRc = await paletteSession.getReturnCode();
        if (!ReturnCode.isSuccess(paletteRc)) {
          throw Exception('Palette generation failed');
        }

        // Pass 2: Encode GIF
        if (mounted) setState(() => _conversionStatus = 'Encoding sticker...');

        final encodeCmd =
            '-ss $startSec -t $durationSec -i "$_videoPath" -i "$palettePath" '
            '-lavfi "$scaleFilter[v];[v][1:v]paletteuse=dither=floyd_steinberg" '
            '-y "$outputPath"';

        final encodeSession = await FFmpegKit.execute(encodeCmd);
        if (_cancelRequested) break;

        final encodeRc = await encodeSession.getReturnCode();
        if (!ReturnCode.isSuccess(encodeRc)) {
          throw Exception('GIF encoding failed');
        }

        // Check size
        final outputFile = File(outputPath);
        final size = await outputFile.length();

        if (size <= StickerGuardrails.maxAnimatedSizeBytes) {
          gifPath = outputPath;
          break;
        }

        // Too large — step down quality
        if (qualityIdx < StickerGuardrails.qualityFpsStops.length - 1) {
          qualityIdx++;
          if (mounted) setState(() => _conversionStatus = 'Optimizing size...');
        } else {
          // Already at lowest quality, use it anyway
          gifPath = outputPath;
          break;
        }
      }

      if (_cancelRequested) {
        _showSnackBar('Conversion cancelled.', AppColors.textSecondary);
        return;
      }

      if (gifPath == null) {
        _showSnackBar(
          "Couldn't convert this video. Try a shorter clip!",
          AppColors.coral,
        );
        return;
      }

      // Decode GIF into frame PNGs for the animated editor
      final gifBytes = await File(gifPath).readAsBytes();
      final decoded = img.decodeGif(gifBytes);

      if (decoded == null || decoded.numFrames == 0) {
        _showSnackBar('GIF decode failed — try again!', AppColors.coral);
        return;
      }

      final framePaths = <String>[];
      for (int i = 0; i < decoded.numFrames; i++) {
        final frame = decoded.getFrame(i);
        final pngBytes = img.encodePng(frame);
        final framePath = '${workDir.path}/frame_$i.png';
        await File(framePath).writeAsBytes(pngBytes);
        framePaths.add(framePath);
      }

      if (!mounted) return;

      // Navigate to animated editor with video-sourced data
      final fps = StickerGuardrails.qualityFpsStops[qualityIdx];
      context.push('/animated-editor', extra: {
        'frames': framePaths,
        'gifPath': gifPath,
        'fps': fps,
      });
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          "Oops! Couldn't convert this video. Try a shorter clip or different video.",
          AppColors.coral,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConverting = false;
          _conversionStatus = '';
        });
      }
    }
  }

  void _cancelConversion() {
    _cancelRequested = true;
    FFmpegKit.cancel();
  }

  // ---------------------------------------------------------------------------
  // Temp file cleanup
  // ---------------------------------------------------------------------------

  void _cleanupTempFiles() {
    // Best-effort cleanup of temp files
    try {
      if (_tempDir != null) {
        final dirs = _tempDir!.listSync().whereType<Directory>();
        for (final dir in dirs) {
          if (dir.path.contains('vtrim_') || dir.path.contains('vconvert_')) {
            dir.deleteSync(recursive: true);
          }
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Video to Sticker'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: _videoController == null
                ? _buildPickerState(theme)
                : _buildEditorState(theme),
          ),
          if (_isConverting) _buildConversionOverlay(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // No video selected state
  // ---------------------------------------------------------------------------

  Widget _buildPickerState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_rounded,
              size: 80,
              color: AppColors.purple.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Pick a Video!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a video and we\'ll turn your favorite '
              'moment into a smooth animated sticker!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            BubblyButton(
              label: _isLoading ? 'Loading...' : 'Choose Video',
              icon: Icons.video_call_rounded,
              color: AppColors.purple,
              isLoading: _isLoading,
              onPressed: _isLoading ? () {} : _pickVideo,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _tipRow(Icons.timer_outlined, 'Select up to 5 seconds'),
                  const SizedBox(height: 8),
                  _tipRow(Icons.tune_rounded, 'Adjust quality vs. smoothness'),
                  const SizedBox(height: 8),
                  _tipRow(Icons.data_usage_rounded, 'Keeps it under 500 KB'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.purple),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Video loaded state
  // ---------------------------------------------------------------------------

  Widget _buildEditorState(ThemeData theme) {
    final controller = _videoController!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video preview
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio.clamp(0.5, 2.0),
              child: VideoPlayer(controller),
            ),
          ),
          const SizedBox(height: 12),

          // Play/pause
          Center(
            child: IconButton(
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                size: 48,
                color: AppColors.coral,
              ),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
            ),
          ),
          const SizedBox(height: 8),

          // Trim scrubber
          Text(
            'Select Clip',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _isGeneratingThumbnails
              ? const SizedBox(
                  height: 80,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Generating preview...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : VideoTrimScrubber(
                  thumbnails: _thumbnails,
                  videoDurationMs:
                      controller.value.duration.inMilliseconds,
                  maxSelectionMs: _kMaxClipDurationMs,
                  minSelectionMs: 500,
                  selectionStart: _trimStart,
                  selectionEnd: _trimEnd,
                  playbackPosition: controller.value.isInitialized
                      ? (controller.value.position.inMilliseconds /
                              controller.value.duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : 0.0,
                  onSelectionChanged: (range) {
                    setState(() {
                      _trimStart = range.start;
                      _trimEnd = range.end;
                    });
                  },
                ),
          const SizedBox(height: 20),

          // Quality vs Smoothness slider
          _buildQualitySlider(theme),
          const SizedBox(height: 16),

          // Size estimation
          _buildSizeEstimate(theme),
          const SizedBox(height: 20),

          // Create sticker button
          BubblyButton(
            label: 'Create Animated Sticker!',
            icon: Icons.celebration_rounded,
            gradient: AppColors.primaryGradient,
            onPressed: _convertToGif,
          ),

          // Pick different video
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Pick Different Video'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Quality slider
  // ---------------------------------------------------------------------------

  Widget _buildQualitySlider(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Quality vs. Smoothness',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _qualityLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Crisp', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Expanded(
              child: Slider(
                value: _qualityIndex.toDouble(),
                min: 0,
                max: 4,
                divisions: 4,
                activeColor: AppColors.purple,
                onChanged: (v) => setState(() => _qualityIndex = v.round()),
              ),
            ),
            const Text('Smooth', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        Center(
          child: Text(
            '${_fps} FPS  |  ${_resolution}px  |  $_maxColors colors',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Size estimation
  // ---------------------------------------------------------------------------

  Widget _buildSizeEstimate(ThemeData theme) {
    final estimateKB = _estimatedSizeKB;
    final estimateBytes = (estimateKB * 1024).round();
    final status = StickerGuardrails.sizeStatus(estimateBytes, isAnimated: true);
    final color = StickerGuardrails.sizeColor(status);
    final fraction = (estimateKB / 500).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.data_usage_rounded, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              'Est. size: ${estimateKB.toStringAsFixed(0)} KB / 500 KB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                StickerGuardrails.sizeTip(status, isAnimated: true),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: Colors.grey.shade200,
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Conversion overlay
  // ---------------------------------------------------------------------------

  Widget _buildConversionOverlay(ThemeData theme) {
    return Container(
      color: Colors.black38,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.symmetric(horizontal: 48),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.purple),
              const SizedBox(height: 16),
              Text(
                _conversionStatus,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _cancelConversion,
                icon: const Icon(Icons.close, color: AppColors.coral),
                label: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.coral),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: No errors in the rewritten file.

- [ ] **Step 3: VALIDATE on emulator — video pick + thumbnails**

```
/ralph-loop "Run the app on emulator with 'flutter run'. Navigate to Video to Sticker. Pick a video from gallery. Verify: 1) Video loads and plays in the preview. 2) Thumbnail strip generates and shows below the video. 3) Duration label shows correctly. Report what you see and then output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 4: VALIDATE on emulator — scrubber handles**

```
/ralph-loop "With a video loaded in Video to Sticker, drag the scrubber handles. Verify: 1) Start/end handles move. 2) Duration label updates in real-time. 3) Max 5s enforced. 4) Min 0.5s enforced. Output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

- [ ] **Step 5: VALIDATE on emulator — quality slider**

```
/ralph-loop "Move the quality slider from Crispest to Smoothest. Verify: 1) Label updates (Crispest/Crisp/Balanced/Smooth/Smoothest). 2) FPS/resolution/colors text updates. 3) Size estimation bar updates. Output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

- [ ] **Step 6: VALIDATE on emulator — FFmpeg conversion**

```
/ralph-loop "Tap 'Create Animated Sticker!' button. Verify: 1) Loading overlay shows with 'Generating color palette...' then 'Encoding sticker...'. 2) Cancel button is visible. 3) After conversion, app navigates to animated editor. 4) Frames are loaded in the editor. Output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 7: VALIDATE on emulator — cancel**

```
/ralph-loop "Start a conversion and immediately tap Cancel. Verify: 1) Conversion stops. 2) Snackbar shows 'Conversion cancelled.' 3) App returns to scrubber view, not crashed. Output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/editor/presentation/video_to_sticker_screen.dart
git commit -m "feat: rewrite video-to-sticker with FFmpeg pipeline and Instagram scrubber"
```

---

### Task 6: Update AnimatedStickerScreen for Video Handoff

**Files:**
- Modify: `lib/features/editor/presentation/animated_sticker_screen.dart`

- [ ] **Step 1: Add video-sourced state fields**

After the `_textAnimation` field (line 71), add:

```dart
  // -- Video-sourced state ---------------------------------------------------
  String? _ffmpegGifPath;
  bool _isVideoSourced = false;
  bool _hasBeenEdited = false;
```

- [ ] **Step 2: Update _loadInitialFrames**

Replace the `_loadInitialFrames` method (lines 84-101) with:

```dart
  Future<void> _loadInitialFrames() async {
    final paths = widget.initialFramePaths;
    if (paths == null || paths.isEmpty) return;

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _framePaths.add(path);
            _frameBytes.add(bytes);
          });
        }
      }
    }

    // Video-sourced sticker setup
    if (widget.ffmpegGifPath != null) {
      _ffmpegGifPath = widget.ffmpegGifPath;
      _isVideoSourced = true;

      // Set FPS from video conversion
      if (widget.initialFps != null) {
        final fps = widget.initialFps!.clamp(
          StickerGuardrails.minFps,
          StickerGuardrails.videoMaxFps,
        );
        _frameDurationMs = (1000 / fps).round();
      }
    }

    _updateSizeEstimate();
  }
```

- [ ] **Step 3: Track edits**

In `_addFrames`, `_removeFrame`, `_onReorder`, `_showAddTextDialog` (where text is applied), add at the start of each method body:

```dart
_hasBeenEdited = true;
```

Specifically, add `_hasBeenEdited = true;` as the first line in:
- `_addFrames()` (after the early return check)
- `_removeFrame()`
- `_onReorder()`
- Inside `_showTextStyleSheet`'s `onApply` and `onApplyWithAnimation` callbacks

- [ ] **Step 4: Update export to use FFmpeg GIF directly when unedited**

In the `_export` method, replace the validation section at the start (lines 427-438) with:

```dart
    // Use video-specific or standard validation
    final errors = _isVideoSourced
        ? StickerGuardrails.validateVideoSticker(
            frameCount: _frameBytes.length,
            fps: _fps,
            sizeBytes: _estimatedSize,
            text: _overlayText,
          )
        : StickerGuardrails.validateAnimatedSticker(
            frameCount: _frameBytes.length,
            estimatedSizeBytes: _estimatedSize,
            fps: _fps,
            overlayText: _overlayText,
          );

    if (errors.isNotEmpty) {
      _showSnackBar(errors.first, AppColors.coral);
      return;
    }
```

Then, after `HapticFeedback.mediumImpact();`, add the no-edit fast path before the existing try block:

```dart
    // Fast path: use FFmpeg GIF directly if no edits were made
    if (_isVideoSourced && !_hasBeenEdited && _ffmpegGifPath != null) {
      try {
        final gifFile = File(_ffmpegGifPath!);
        if (await gifFile.exists()) {
          final directory = await getApplicationDocumentsDirectory();
          final stickersDir = Directory('${directory.path}/stickers');
          if (!await stickersDir.exists()) {
            await stickersDir.create(recursive: true);
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filePath = '${stickersDir.path}/animated_$timestamp.gif';
          await gifFile.copy(filePath);

          if (!mounted) return;
          setState(() => _isExporting = false);
          await _showSaveToPackDialog(filePath);
          return;
        }
      } catch (_) {
        // Fall through to standard export
      }
    }
```

- [ ] **Step 5: Update FPS slider range for video-sourced stickers**

In `_buildControls`, update the Slider widget to use video-specific max when appropriate. Replace the FPS Slider (around line 1295-1300):

```dart
                  child: Slider(
                    value: _fps.toDouble().clamp(
                      StickerGuardrails.minFps.toDouble(),
                      (_isVideoSourced
                              ? StickerGuardrails.videoMaxFps
                              : StickerGuardrails.maxFps)
                          .toDouble(),
                    ),
                    min: StickerGuardrails.minFps.toDouble(),
                    max: (_isVideoSourced
                            ? StickerGuardrails.videoMaxFps
                            : StickerGuardrails.maxFps)
                        .toDouble(),
                    divisions: (_isVideoSourced
                            ? StickerGuardrails.videoMaxFps
                            : StickerGuardrails.maxFps) -
                        StickerGuardrails.minFps,
                    onChanged: (v) => _setFps(v),
                  ),
```

- [ ] **Step 6: Update _setFps to handle video-sourced range**

Replace `_setFps` method:

```dart
  void _setFps(double fps) {
    final maxFps = _isVideoSourced
        ? StickerGuardrails.videoMaxFps
        : StickerGuardrails.maxFps;
    final clamped = fps.clamp(
      StickerGuardrails.minFps.toDouble(),
      maxFps.toDouble(),
    );
    setState(() {
      _frameDurationMs = (1000 / clamped).round();
    });
    if (_isPlaying) {
      _stopAnimation();
      _startAnimation();
    }
  }
```

- [ ] **Step 7: Update frame count display for video-sourced**

In `_buildFrameStrip`, update the frame count badge to show video max:

```dart
            child: Text(
              '${_framePaths.length}/${_isVideoSourced ? 'video' : '$_kMaxFrames'}',
```

- [ ] **Step 8: Run tests**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 9: VALIDATE on emulator — video handoff**

```
/ralph-loop "Pick a video, trim it, convert. In the animated editor verify: 1) Frames are loaded. 2) Animation preview plays smoothly. 3) FPS slider shows the video FPS. 4) Export without editing — verify it saves quickly (fast path). 5) Save to pack works. Output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 10: VALIDATE on emulator — edit + re-export**

```
/ralph-loop "Pick video, convert, in animated editor add text overlay. Export. Verify: 1) Text is burned into the GIF frames. 2) Save to pack works. 3) No crash. Output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 11: VALIDATE on emulator — manual flow still works**

```
/ralph-loop "Navigate to Create > Animated Sticker (NOT from video). Verify: 1) Empty state shows. 2) Add frames manually. 3) FPS slider goes 4-8. 4) Export works. 5) Save to pack works. The manual flow must be unbroken. Output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 12: Commit**

```bash
git add lib/features/editor/presentation/animated_sticker_screen.dart
git commit -m "feat: add video-sourced sticker support with FFmpeg GIF fast path"
```

---

### Task 7: End-to-End Validation

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass. Zero regressions.

- [ ] **Step 2: VALIDATE full end-to-end on emulator**

```
/ralph-loop "Complete end-to-end test: 1) Open app. 2) Go to Video to Sticker. 3) Pick video. 4) Trim to ~3 seconds. 5) Set quality to Balanced. 6) Convert. 7) In animated editor, add text 'LOL'. 8) Export. 9) Save to new pack 'Video Stickers'. 10) Verify pack shows in My Packs. 11) Verify sticker thumbnail is visible. Full flow must work. Output <promise>VALIDATED</promise>" --max-iterations 8 --completion-promise "VALIDATED"
```

- [ ] **Step 3: VALIDATE edge cases on emulator**

```
/ralph-loop "Test edge cases: 1) Pick a very short video (<2 seconds). Verify it uses the full video, no crash. 2) Pick a long video (>30 seconds). Verify scrubber is scrollable, trim works. 3) Try a portrait video. Verify GIF is square with transparent padding. Report findings. Output <promise>VALIDATED</promise>" --max-iterations 5 --completion-promise "VALIDATED"
```

- [ ] **Step 4: VALIDATE temp cleanup**

```
/ralph-loop "After completing a full video-to-sticker flow, check the app's temp directory for leftover vtrim_ and vconvert_ folders. They should be cleaned up. Output <promise>VALIDATED</promise>" --max-iterations 3 --completion-promise "VALIDATED"
```

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete video-to-sticker redesign with FFmpeg pipeline"
```
