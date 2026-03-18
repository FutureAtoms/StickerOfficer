import 'package:flutter/material.dart';

/// A small status indicator that shows whether a sticker's file size is within
/// WhatsApp's limits.
///
/// Thresholds for **static** stickers (default):
///   - Green : under 80 KB  -- "Perfect size!"
///   - Yellow: 80 - 100 KB  -- "Getting big..."
///   - Red   : over 100 KB  -- "Too large for WhatsApp"
///
/// Thresholds for **animated** stickers ([isAnimated] = true):
///   - Green : under 400 KB
///   - Yellow: 400 - 500 KB
///   - Red   : over 500 KB
class StickerSizeIndicator extends StatelessWidget {
  /// Size of the sticker data in bytes.
  final int sizeInBytes;

  /// Whether the sticker is animated (uses larger thresholds).
  final bool isAnimated;

  const StickerSizeIndicator({
    super.key,
    required this.sizeInBytes,
    this.isAnimated = false,
  });

  @override
  Widget build(BuildContext context) {
    final sizeKB = sizeInBytes / 1024;

    final double greenThreshold;
    final double redThreshold;

    if (isAnimated) {
      greenThreshold = 400;
      redThreshold = 500;
    } else {
      greenThreshold = 80;
      redThreshold = 100;
    }

    final Color dotColor;
    final String label;

    if (sizeKB <= greenThreshold) {
      dotColor = Colors.green;
      label = 'Perfect size!';
    } else if (sizeKB <= redThreshold) {
      dotColor = Colors.orange;
      label = 'Getting big...';
    } else {
      dotColor = Colors.red;
      label = 'Too large for WhatsApp';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$label (${sizeKB.toStringAsFixed(0)} KB)',
            style: TextStyle(
              color: dotColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
