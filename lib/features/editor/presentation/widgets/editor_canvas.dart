import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../editor_screen.dart';

class EditorCanvas extends StatelessWidget {
  final ui.Image? image;
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final String? overlayText;
  final Offset textPosition;
  final bool hasRemovedBg;
  final EditorTool selectedTool;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;
  final VoidCallback onStrokeEnd;

  const EditorCanvas({
    super.key,
    this.image,
    required this.strokes,
    required this.currentStroke,
    this.overlayText,
    required this.textPosition,
    required this.hasRemovedBg,
    required this.selectedTool,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: GestureDetector(
          onPanStart: (details) => onStrokeStart(details.localPosition),
          onPanUpdate: (details) => onStrokeUpdate(details.localPosition),
          onPanEnd: (_) => onStrokeEnd(),
          child: CustomPaint(
            painter: _CanvasPainter(
              image: image,
              strokes: strokes,
              currentStroke: currentStroke,
              overlayText: overlayText,
              textPosition: textPosition,
              hasRemovedBg: hasRemovedBg,
              selectedTool: selectedTool,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final ui.Image? image;
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final String? overlayText;
  final Offset textPosition;
  final bool hasRemovedBg;
  final EditorTool selectedTool;

  _CanvasPainter({
    this.image,
    required this.strokes,
    required this.currentStroke,
    this.overlayText,
    required this.textPosition,
    required this.hasRemovedBg,
    required this.selectedTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw checkerboard background (transparency indicator)
    _drawCheckerboard(canvas, size);

    // Draw placeholder if no image
    if (image == null) {
      _drawPlaceholder(canvas, size);
    } else {
      // Draw the image
      final paint = Paint();
      canvas.drawImage(image!, Offset.zero, paint);
    }

    // Draw strokes
    final strokePaint =
        Paint()
          ..color =
              selectedTool == EditorTool.eraser ? Colors.white : AppColors.coral
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }

    // Draw current stroke
    if (currentStroke.length >= 2) {
      final path = Path()..moveTo(currentStroke[0].dx, currentStroke[0].dy);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }

    // Draw overlay text
    if (overlayText != null && overlayText!.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: overlayText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);
      textPainter.paint(canvas, textPosition);
    }
  }

  void _drawCheckerboard(Canvas canvas, Size size) {
    const tileSize = 20.0;
    final paint1 = Paint()..color = const Color(0xFFE8E8E8);
    final paint2 = Paint()..color = const Color(0xFFD0D0D0);

    for (double x = 0; x < size.width; x += tileSize) {
      for (double y = 0; y < size.height; y += tileSize) {
        final isEven =
            ((x / tileSize).floor() + (y / tileSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, tileSize, tileSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.pastels[4].withOpacity(0.5)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.2,
          size.height * 0.25,
          size.width * 0.6,
          size.height * 0.5,
        ),
        const Radius.circular(20),
      ),
      paint,
    );

    // Draw placeholder icon
    final iconPaint =
        Paint()
          ..color = AppColors.purple.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 30, iconPaint);

    // Plus sign
    canvas.drawLine(
      center - const Offset(12, 0),
      center + const Offset(12, 0),
      iconPaint,
    );
    canvas.drawLine(
      center - const Offset(0, 12),
      center + const Offset(0, 12),
      iconPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
