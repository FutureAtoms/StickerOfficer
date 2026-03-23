import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/text_style_sheet.dart';
import '../editor_screen.dart';

class StrokeData {
  const StrokeData({
    required this.points,
    this.isEraser = false,
    this.color = AppColors.coral,
    this.size = 10,
  });

  final List<Offset> points;
  final bool isEraser;
  final Color color;
  final double size;
}

class CanvasPointerData {
  const CanvasPointerData({
    required this.canvasPosition,
    required this.imagePosition,
    required this.imageRect,
    required this.canvasSize,
  });

  final Offset canvasPosition;
  final Offset? imagePosition;
  final Rect imageRect;
  final Size canvasSize;

  bool get isInsideImage => imagePosition != null;
}

class EditorViewport {
  const EditorViewport({
    required this.canvasSize,
    required this.imageRect,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Size canvasSize;
  final Rect imageRect;
  final double imageWidth;
  final double imageHeight;

  factory EditorViewport.fromImage(ui.Image? image, Size canvasSize) {
    if (image == null || canvasSize.isEmpty) {
      return EditorViewport(
        canvasSize: canvasSize,
        imageRect: Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
        imageWidth: canvasSize.width <= 0 ? 1 : canvasSize.width,
        imageHeight: canvasSize.height <= 0 ? 1 : canvasSize.height,
      );
    }

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final scale = mathMin(canvasSize.width / imgW, canvasSize.height / imgH);
    final destW = imgW * scale;
    final destH = imgH * scale;
    final dx = (canvasSize.width - destW) / 2;
    final dy = (canvasSize.height - destH) / 2;

    return EditorViewport(
      canvasSize: canvasSize,
      imageRect: Rect.fromLTWH(dx, dy, destW, destH),
      imageWidth: imgW,
      imageHeight: imgH,
    );
  }

  Offset imageToCanvas(Offset imagePoint) {
    if (imageRect.width == 0 || imageRect.height == 0) {
      return imagePoint;
    }
    return Offset(
      imageRect.left + (imagePoint.dx / imageWidth) * imageRect.width,
      imageRect.top + (imagePoint.dy / imageHeight) * imageRect.height,
    );
  }

  Rect imageRectToCanvas(Rect imageBounds) {
    final topLeft = imageToCanvas(imageBounds.topLeft);
    final bottomRight = imageToCanvas(imageBounds.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  Offset? canvasToImage(Offset canvasPoint) {
    if (!imageRect.contains(canvasPoint) ||
        imageRect.width == 0 ||
        imageRect.height == 0) {
      return null;
    }
    return Offset(
      ((canvasPoint.dx - imageRect.left) / imageRect.width * imageWidth)
          .clamp(0.0, imageWidth - 1)
          .toDouble(),
      ((canvasPoint.dy - imageRect.top) / imageRect.height * imageHeight)
          .clamp(0.0, imageHeight - 1)
          .toDouble(),
    );
  }

  Offset canvasToImageClamped(Offset canvasPoint) {
    final clamped = Offset(
      canvasPoint.dx.clamp(imageRect.left, imageRect.right).toDouble(),
      canvasPoint.dy.clamp(imageRect.top, imageRect.bottom).toDouble(),
    );
    return canvasToImage(clamped) ?? Offset.zero;
  }
}

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    this.image,
    required this.strokes,
    required this.currentStroke,
    required this.currentSelectionPath,
    this.currentStrokeIsEraser = false,
    this.currentStrokeColor = AppColors.coral,
    this.currentStrokeSize = 10,
    this.overlayText,
    required this.textPosition,
    this.textStyle = const StickerTextStyle(),
    this.isTextSelected = false,
    required this.hasRemovedBg,
    required this.selectedTool,
    required this.selectionPolygon,
    this.cropRect,
    this.isCropping = false,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onTextDrag,
    this.onTextTap,
    this.onTapPlaceholder,
    this.onCanvasTap,
  });

  final ui.Image? image;
  final List<StrokeData> strokes;
  final List<Offset> currentStroke;
  final List<Offset> currentSelectionPath;
  final bool currentStrokeIsEraser;
  final Color currentStrokeColor;
  final double currentStrokeSize;
  final String? overlayText;
  final Offset textPosition;
  final StickerTextStyle textStyle;
  final bool isTextSelected;
  final bool hasRemovedBg;
  final EditorTool selectedTool;
  final List<Offset> selectionPolygon;
  final Rect? cropRect;
  final bool isCropping;
  final ValueChanged<CanvasPointerData> onPanStart;
  final ValueChanged<CanvasPointerData> onPanUpdate;
  final VoidCallback onPanEnd;
  final ValueChanged<Offset> onTextDrag;
  final VoidCallback? onTextTap;
  final VoidCallback? onTapPlaceholder;
  final VoidCallback? onCanvasTap;

  /// Convenience getters that delegate to [textStyle] for test accessibility.
  Color get textColor => textStyle.color;
  double get textSize => textStyle.size;
  bool get textBold => textStyle.bold;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final viewport = EditorViewport.fromImage(image, canvasSize);
            final textCanvasPosition =
                image == null
                    ? textPosition
                    : viewport.imageToCanvas(textPosition);

            CanvasPointerData pointerData(Offset canvasPosition) {
              return CanvasPointerData(
                canvasPosition: canvasPosition,
                imagePosition:
                    image == null
                        ? null
                        : viewport.canvasToImage(canvasPosition),
                imageRect: viewport.imageRect,
                canvasSize: canvasSize,
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (image == null) {
                        onTapPlaceholder?.call();
                      } else {
                        onCanvasTap?.call();
                      }
                    },
                    onPanStart:
                        (details) =>
                            onPanStart(pointerData(details.localPosition)),
                    onPanUpdate:
                        (details) =>
                            onPanUpdate(pointerData(details.localPosition)),
                    onPanEnd: (_) => onPanEnd(),
                    child: CustomPaint(
                      painter: _CanvasPainter(
                        image: image,
                        viewport: viewport,
                        strokes: strokes,
                        currentStroke: currentStroke,
                        currentSelectionPath: currentSelectionPath,
                        currentStrokeIsEraser: currentStrokeIsEraser,
                        currentStrokeColor: currentStrokeColor,
                        currentStrokeSize: currentStrokeSize,
                        hasRemovedBg: hasRemovedBg,
                        selectedTool: selectedTool,
                        selectionPolygon: selectionPolygon,
                        cropRect: cropRect,
                        isCropping: isCropping,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                if (overlayText != null && overlayText!.isNotEmpty)
                  Positioned(
                    left: textCanvasPosition.dx,
                    top: textCanvasPosition.dy,
                    child: GestureDetector(
                      onTap: onTextTap,
                      onPanUpdate:
                          isCropping
                              ? null
                              : (details) {
                                final nextCanvasPosition =
                                    textCanvasPosition + details.delta;
                                if (image == null) {
                                  onTextDrag(nextCanvasPosition);
                                  return;
                                }
                                onTextDrag(
                                  viewport.canvasToImageClamped(
                                    nextCanvasPosition,
                                  ),
                                );
                              },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration:
                            isTextSelected
                                ? BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.coral,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                )
                                : null,
                        child: Stack(
                          children: [
                            if (textStyle.hasOutline)
                              Text(
                                overlayText!,
                                style: textStyle.toOutlineTextStyle(),
                              ),
                            Text(overlayText!, style: textStyle.toTextStyle()),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.image,
    required this.viewport,
    required this.strokes,
    required this.currentStroke,
    required this.currentSelectionPath,
    required this.currentStrokeIsEraser,
    required this.currentStrokeColor,
    required this.currentStrokeSize,
    required this.hasRemovedBg,
    required this.selectedTool,
    required this.selectionPolygon,
    required this.cropRect,
    required this.isCropping,
  });

  final ui.Image? image;
  final EditorViewport viewport;
  final List<StrokeData> strokes;
  final List<Offset> currentStroke;
  final List<Offset> currentSelectionPath;
  final bool currentStrokeIsEraser;
  final Color currentStrokeColor;
  final double currentStrokeSize;
  final bool hasRemovedBg;
  final EditorTool selectedTool;
  final List<Offset> selectionPolygon;
  final Rect? cropRect;
  final bool isCropping;

  @override
  void paint(Canvas canvas, Size size) {
    _drawCheckerboard(canvas, size);

    if (image == null) {
      _drawPlaceholder(canvas, size);
      return;
    }

    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
      viewport.imageRect,
      Paint(),
    );

    for (final stroke in strokes) {
      _drawStrokePreview(
        canvas,
        stroke.points,
        color: stroke.color,
        size: stroke.size,
        isEraser: stroke.isEraser,
      );
    }

    if (currentStroke.isNotEmpty) {
      _drawStrokePreview(
        canvas,
        currentStroke,
        color: currentStrokeColor,
        size: currentStrokeSize,
        isEraser: currentStrokeIsEraser,
      );
    }

    if (selectionPolygon.length >= 3) {
      _drawSelectionOverlay(canvas, size, selectionPolygon);
    }

    if (selectedTool == EditorTool.lasso && currentSelectionPath.length >= 2) {
      _drawSelectionPath(
        canvas,
        currentSelectionPath,
        color: AppColors.coral,
        strokeWidth: 2.5,
      );
    }

    if (isCropping && cropRect != null) {
      _drawCropOverlay(canvas, size, cropRect!);
    }
  }

  void _drawStrokePreview(
    Canvas canvas,
    List<Offset> points, {
    required Color color,
    required double size,
    required bool isEraser,
  }) {
    final canvasPoints = points
        .map(viewport.imageToCanvas)
        .toList(growable: false);
    final path = _buildStrokePath(canvasPoints, size);
    if (path == null) {
      return;
    }

    final previewColor =
        isEraser
            ? Colors.orange.withValues(alpha: 0.28)
            : color.withValues(alpha: 0.78);
    canvas.drawPath(path, Paint()..color = previewColor);
  }

  void _drawSelectionOverlay(Canvas canvas, Size size, List<Offset> polygon) {
    final canvasPolygon = polygon
        .map(viewport.imageToCanvas)
        .toList(growable: false);
    final selectionPath = Path()..addPolygon(canvasPolygon, true);
    final outsidePath =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addPath(selectionPath, Offset.zero);

    canvas.drawPath(
      outsidePath,
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
    canvas.drawPath(
      selectionPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.92),
    );
    _drawSelectionPath(
      canvas,
      polygon,
      color: AppColors.coral,
      strokeWidth: 1.5,
    );
  }

  void _drawSelectionPath(
    Canvas canvas,
    List<Offset> polygon, {
    required Color color,
    required double strokeWidth,
  }) {
    final canvasPolygon = polygon
        .map(viewport.imageToCanvas)
        .toList(growable: false);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(canvasPolygon.first.dx, canvasPolygon.first.dy);
    for (var index = 1; index < canvasPolygon.length; index++) {
      path.lineTo(canvasPolygon[index].dx, canvasPolygon[index].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawCropOverlay(Canvas canvas, Size size, Rect imageCropRect) {
    final cropCanvasRect = viewport.imageRectToCanvas(imageCropRect);
    final outsidePath =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addRect(cropCanvasRect);
    canvas.drawPath(
      outsidePath,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    canvas.drawRect(
      cropCanvasRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    final guidePaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = 1;
    final thirdWidth = cropCanvasRect.width / 3;
    final thirdHeight = cropCanvasRect.height / 3;
    for (var index = 1; index <= 2; index++) {
      final dx = cropCanvasRect.left + thirdWidth * index;
      final dy = cropCanvasRect.top + thirdHeight * index;
      canvas.drawLine(
        Offset(dx, cropCanvasRect.top),
        Offset(dx, cropCanvasRect.bottom),
        guidePaint,
      );
      canvas.drawLine(
        Offset(cropCanvasRect.left, dy),
        Offset(cropCanvasRect.right, dy),
        guidePaint,
      );
    }

    final handlePaint = Paint()..color = AppColors.coral;
    for (final handle in [
      cropCanvasRect.topLeft,
      cropCanvasRect.topRight,
      cropCanvasRect.bottomLeft,
      cropCanvasRect.bottomRight,
    ]) {
      canvas.drawCircle(handle, 8, handlePaint);
      canvas.drawCircle(
        handle,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  Path? _buildStrokePath(List<Offset> points, double size) {
    if (points.isEmpty) {
      return null;
    }

    final strokeOutline = getStroke(
      points.map((point) => PointVector.fromOffset(offset: point)).toList(),
      options: StrokeOptions(
        size: size,
        thinning: 0,
        smoothing: 0.65,
        streamline: 0.38,
        simulatePressure: true,
        isComplete: true,
      ),
    );

    if (strokeOutline.isEmpty) {
      return null;
    }

    final path = Path()..moveTo(strokeOutline.first.dx, strokeOutline.first.dy);
    for (var index = 1; index < strokeOutline.length; index++) {
      final previous = strokeOutline[index - 1];
      final current = strokeOutline[index];
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
    }
    path.close();
    return path;
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
          ..color = AppColors.pastels[4].withValues(alpha: 0.5)
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

    final iconPaint =
        Paint()
          ..color = AppColors.purple.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    final center = Offset(size.width / 2, size.height / 2 - 16);
    canvas.drawCircle(center, 30, iconPaint);
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

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Tap to pick a photo',
        style: TextStyle(
          color: AppColors.purple.withValues(alpha: 0.6),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.6);
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, center.dy + 48),
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return image != oldDelegate.image ||
        strokes != oldDelegate.strokes ||
        currentStroke != oldDelegate.currentStroke ||
        currentSelectionPath != oldDelegate.currentSelectionPath ||
        currentStrokeIsEraser != oldDelegate.currentStrokeIsEraser ||
        currentStrokeColor != oldDelegate.currentStrokeColor ||
        currentStrokeSize != oldDelegate.currentStrokeSize ||
        hasRemovedBg != oldDelegate.hasRemovedBg ||
        selectedTool != oldDelegate.selectedTool ||
        selectionPolygon != oldDelegate.selectionPolygon ||
        cropRect != oldDelegate.cropRect ||
        isCropping != oldDelegate.isCropping;
  }
}

double mathMin(double a, double b) => a < b ? a : b;
