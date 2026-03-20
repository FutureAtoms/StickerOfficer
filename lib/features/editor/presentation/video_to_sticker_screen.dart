import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
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

/// Max video clip duration for sticker creation.
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

  // Quality slider (0-4 index into qualityFpsStops)
  int _qualityIndex = 2; // Default: Balanced

  // Conversion state
  bool _isConverting = false;
  String _conversionStatus = '';
  bool _cancelRequested = false;

  // Temp directory for this session
  String? _sessionTempPath;

  void _videoListener() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoListener);
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
    return (totalMs * (_trimEnd - _trimStart)) / 1000.0;
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

      _videoController?.removeListener(_videoListener);
      _videoController?.dispose();
      controller.addListener(_videoListener);

      setState(() {
        _videoController = controller;
        _videoPath = video.path;
        _trimStart = 0.0;
        _trimEnd = trimEnd;
        _isLoading = false;
      });

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
      final tempDir = await getTemporaryDirectory();
      final thumbDir = Directory(
        '${tempDir.path}/vtrim_${DateTime.now().millisecondsSinceEpoch}',
      );
      await thumbDir.create(recursive: true);
      _sessionTempPath = tempDir.path;

      final durationSec =
          _videoController!.value.duration.inMilliseconds / 1000.0;
      // ~2 thumbnails per second, capped at 60
      final count = (durationSec * 2).clamp(4, 60).round();
      final fps = count / durationSec;

      final command =
          '-i "$_videoPath" -vf "fps=$fps:round=near,scale=80:-1" '
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
    } catch (_) {
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
      _showSnackBar(
        'Clip is too short! Select at least 0.5 seconds.',
        AppColors.coral,
      );
      return;
    }

    setState(() {
      _isConverting = true;
      _cancelRequested = false;
      _conversionStatus = 'Generating color palette...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final workDir = Directory(
        '${tempDir.path}/vconvert_${DateTime.now().millisecondsSinceEpoch}',
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
        if (mounted) {
          setState(() => _conversionStatus = 'Generating color palette...');
        }

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
        if (mounted) {
          setState(() => _conversionStatus = 'Encoding sticker...');
        }

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
          if (mounted) {
            setState(() => _conversionStatus = 'Optimizing size...');
          }
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
  // Cleanup
  // ---------------------------------------------------------------------------

  void _cleanupTempFiles() {
    try {
      if (_sessionTempPath != null) {
        final tempDir = Directory(_sessionTempPath!);
        for (final entity in tempDir.listSync()) {
          if (entity is Directory &&
              (entity.path.contains('vtrim_') ||
                  entity.path.contains('vconvert_'))) {
            entity.deleteSync(recursive: true);
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
  // No video selected
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
              child: const Column(
                children: [
                  _TipRow(Icons.timer_outlined, 'Select up to 5 seconds'),
                  SizedBox(height: 8),
                  _TipRow(Icons.tune_rounded, 'Adjust quality vs. smoothness'),
                  SizedBox(height: 8),
                  _TipRow(Icons.data_usage_rounded, 'Keeps it under 500 KB'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Video loaded
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

          // Quality slider
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            const Text(
              'Crisp',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            Expanded(
              child: Slider(
                value: _qualityIndex.toDouble(),
                min: 0,
                max: 4,
                divisions: 4,
                activeColor: AppColors.purple,
                onChanged: (v) =>
                    setState(() => _qualityIndex = v.round()),
              ),
            ),
            const Text(
              'Smooth',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        Center(
          child: Text(
            '$_fps FPS  |  ${_resolution}px  |  $_maxColors colors',
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
    final status =
        StickerGuardrails.sizeStatus(estimateBytes, isAnimated: true);
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

/// Small helper widget for tip rows in the picker state.
class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
