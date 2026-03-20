import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// Instagram-style video trim scrubber with thumbnail strip and draggable handles.
class VideoTrimScrubber extends StatefulWidget {
  final List<Uint8List> thumbnails;
  final int videoDurationMs;
  final int maxSelectionMs;
  final int minSelectionMs;
  final double selectionStart;
  final double selectionEnd;
  final double playbackPosition;
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

              // Dim overlay - left
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

              // Dim overlay - right
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
                width: totalWidth *
                    (widget.selectionEnd - widget.selectionStart),
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
                left: _handleWidth +
                    totalWidth * widget.playbackPosition -
                    1,
                top: 10,
                child: Container(
                  width: 2,
                  height: _thumbHeight + 4,
                  color: Colors.white,
                ),
              ),

              // Left handle
              Positioned(
                left: _handleWidth +
                    totalWidth * widget.selectionStart -
                    _handleWidth / 2,
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
                left: _handleWidth +
                    totalWidth * widget.selectionEnd -
                    _handleWidth / 2,
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
                child: Center(child: _buildDurationLabel()),
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

    final minFraction = widget.minSelectionMs / widget.videoDurationMs;
    if (widget.selectionEnd - newStart < minFraction) {
      newStart = widget.selectionEnd - minFraction;
    }

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

    final minFraction = widget.minSelectionMs / widget.videoDurationMs;
    if (newEnd - widget.selectionStart < minFraction) {
      newEnd = widget.selectionStart + minFraction;
    }

    final maxFraction = widget.maxSelectionMs / widget.videoDurationMs;
    if (newEnd - widget.selectionStart > maxFraction) {
      newEnd = widget.selectionStart + maxFraction;
    }

    widget.onSelectionChanged(RangeValues(widget.selectionStart, newEnd));
  }
}
