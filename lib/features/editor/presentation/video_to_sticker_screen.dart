import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';

/// Max video duration allowed for sticker creation (seconds).
const _kMaxVideoDurationSec = 5;

/// Max number of frames to extract.
const _kMaxFrames = StickerGuardrails.maxFrames;

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

  // Extracted frames
  final List<Uint8List> _extractedFrames = [];
  final List<String> _framePaths = [];
  bool _isExtracting = false;
  int _frameCount = 4; // default number of frames to extract


  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Video picking
  // ---------------------------------------------------------------------------

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (video == null) return;

      setState(() => _isLoading = true);

      final controller = VideoPlayerController.file(File(video.path));
      await controller.initialize();

      final durationSec = controller.value.duration.inSeconds;

      if (durationSec > _kMaxVideoDurationSec) {
        // Auto-trim to first 5 seconds
        setState(() {
          _trimEnd = _kMaxVideoDurationSec / durationSec;
        });
        _showSnackBar(
          'Video trimmed to $_kMaxVideoDurationSec seconds — '
          'stickers work best when short!',
          Colors.orange,
        );
      }

      setState(() {
        _videoController?.dispose();
        _videoController = controller;
        _videoPath = video.path;
        _extractedFrames.clear();
        _framePaths.clear();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Couldn\'t load video — try another!', AppColors.coral);
    }
  }

  // ---------------------------------------------------------------------------
  // Frame extraction
  // ---------------------------------------------------------------------------

  Future<void> _extractFrames() async {
    if (_videoController == null || _videoPath == null) return;

    setState(() {
      _isExtracting = true;
      _extractedFrames.clear();
      _framePaths.clear();
    });

    try {
      final duration = _videoController!.value.duration;
      final startMs = (duration.inMilliseconds * _trimStart).round();
      final endMs = (duration.inMilliseconds * _trimEnd).round();
      final clipMs = endMs - startMs;

      if (clipMs <= 0) {
        _showSnackBar('Clip is too short!', AppColors.coral);
        setState(() => _isExtracting = false);
        return;
      }

      final count = _frameCount.clamp(2, _kMaxFrames);
      final intervalMs = clipMs ~/ count;
      final tempDir = await getTemporaryDirectory();

      for (var i = 0; i < count; i++) {
        final positionMs = startMs + (intervalMs * i);

        final thumbBytes = await VideoThumbnail.thumbnailData(
          video: _videoPath!,
          imageFormat: ImageFormat.PNG,
          timeMs: positionMs,
          maxWidth: StickerGuardrails.stickerSize,
          maxHeight: StickerGuardrails.stickerSize,
          quality: 85,
        );

        if (thumbBytes == null) continue;

        final path =
            '${tempDir.path}/vframe_${DateTime.now().millisecondsSinceEpoch}_$i.png';
        await File(path).writeAsBytes(thumbBytes);

        setState(() {
          _extractedFrames.add(thumbBytes);
          _framePaths.add(path);
        });
      }

      if (_extractedFrames.length < 2) {
        _showSnackBar(
          'Could only get ${_extractedFrames.length} frame(s) — try a longer clip!',
          AppColors.coral,
        );
      } else {
        _showSnackBar(
          'Got ${_extractedFrames.length} frames!',
          AppColors.success,
        );
      }
    } catch (e) {
      _showSnackBar('Frame extraction failed — try another video!', AppColors.coral);
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Send frames to animated sticker editor
  // ---------------------------------------------------------------------------

  void _openInAnimatedEditor() {
    if (_framePaths.length < 2) {
      _showSnackBar(
        'Need at least 2 frames — extract more!',
        AppColors.coral,
      );
      return;
    }

    // Navigate to animated editor with extracted frames
    context.push('/animated-editor', extra: _framePaths);
  }

  // ---------------------------------------------------------------------------
  // Quick export as GIF directly
  // ---------------------------------------------------------------------------

  // Export is handled by navigating to the animated editor with extracted frames

  // ---------------------------------------------------------------------------
  // Duration helpers
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${mins.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Duration get _clipDuration {
    if (_videoController == null) return Duration.zero;
    final total = _videoController!.value.duration;
    final startMs = (total.inMilliseconds * _trimStart).round();
    final endMs = (total.inMilliseconds * _trimEnd).round();
    return Duration(milliseconds: endMs - startMs);
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
      body: SafeArea(
        child: _videoController == null ? _buildPickerState(theme) : _buildEditorState(theme),
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
              color: AppColors.purple.withOpacity(0.4),
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
              'Choose a short video (up to ${_kMaxVideoDurationSec}s) '
              'and we\'ll turn it into an animated sticker!',
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
                color: AppColors.purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _tipRow(Icons.timer_outlined, 'Max $_kMaxVideoDurationSec seconds'),
                  const SizedBox(height: 8),
                  _tipRow(Icons.photo_library_outlined, 'Extracts up to $_kMaxFrames frames'),
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
          style: TextStyle(
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
    final duration = controller.value.duration;

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

          // Trim controls
          Text(
            'Select Clip',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatDuration(Duration(
                  milliseconds: (duration.inMilliseconds * _trimStart).round(),
                )),
                style: theme.textTheme.bodySmall,
              ),
              Expanded(
                child: RangeSlider(
                  values: RangeValues(_trimStart, _trimEnd),
                  onChanged: (values) {
                    // Enforce max duration
                    final maxFraction = _kMaxVideoDurationSec / duration.inSeconds.clamp(1, 9999);
                    var start = values.start;
                    var end = values.end;
                    if (end - start > maxFraction) {
                      // Clamp the range
                      end = (start + maxFraction).clamp(0.0, 1.0);
                    }
                    setState(() {
                      _trimStart = start;
                      _trimEnd = end;
                    });
                  },
                  activeColor: AppColors.purple,
                  inactiveColor: AppColors.purple.withOpacity(0.2),
                ),
              ),
              Text(
                _formatDuration(Duration(
                  milliseconds: (duration.inMilliseconds * _trimEnd).round(),
                )),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),

          // Clip duration + guardrail
          _buildClipInfo(theme),
          const SizedBox(height: 16),

          // Frame count selector
          Text(
            'Number of Frames',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$_frameCount frames',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _frameCount.toDouble(),
                  min: 2,
                  max: _kMaxFrames.toDouble(),
                  divisions: _kMaxFrames - 2,
                  activeColor: AppColors.purple,
                  label: '$_frameCount',
                  onChanged: (v) => setState(() => _frameCount = v.round()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Extract button
          BubblyButton(
            label: _isExtracting ? 'Extracting...' : 'Extract Frames',
            icon: Icons.auto_awesome_rounded,
            color: AppColors.teal,
            isLoading: _isExtracting,
            onPressed: _isExtracting ? () {} : _extractFrames,
          ),
          const SizedBox(height: 16),

          // Extracted frames preview
          if (_extractedFrames.isNotEmpty) ...[
            Text(
              'Extracted Frames (${_extractedFrames.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _extractedFrames.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _extractedFrames[index],
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Size estimate
            _buildSizeEstimate(theme),
            const SizedBox(height: 16),

            // Create sticker button
            BubblyButton(
              label: 'Create Animated Sticker!',
              icon: Icons.celebration_rounded,
              gradient: AppColors.primaryGradient,
              onPressed: _openInAnimatedEditor,
            ),
          ],

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

  Widget _buildClipInfo(ThemeData theme) {
    final clip = _clipDuration;
    final isTooLong = clip.inSeconds > _kMaxVideoDurationSec;
    final isTooShort = clip.inMilliseconds < 200;

    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 18,
          color: isTooLong || isTooShort ? AppColors.coral : AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'Clip: ${_formatDuration(clip)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isTooLong || isTooShort ? AppColors.coral : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isTooLong) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.coral.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Max ${_kMaxVideoDurationSec}s!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.coral,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ],
        if (isTooShort) ...[
          const SizedBox(width: 8),
          Text(
            'Too short!',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.coral,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSizeEstimate(ThemeData theme) {
    final rawSum = _extractedFrames.fold<int>(0, (s, b) => s + b.length);
    final estimate = (rawSum * 0.6).round();
    final status = StickerGuardrails.sizeStatus(estimate, isAnimated: true);

    return Row(
      children: [
        Icon(
          Icons.data_usage_rounded,
          size: 18,
          color: StickerGuardrails.sizeColor(status),
        ),
        const SizedBox(width: 6),
        Text(
          'Est. size: ${StickerGuardrails.sizeLabel(estimate)} / 500 KB',
          style: theme.textTheme.bodySmall?.copyWith(
            color: StickerGuardrails.sizeColor(status),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: StickerGuardrails.sizeColor(status).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            StickerGuardrails.sizeTip(status, isAnimated: true),
            style: theme.textTheme.bodySmall?.copyWith(
              color: StickerGuardrails.sizeColor(status),
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}
