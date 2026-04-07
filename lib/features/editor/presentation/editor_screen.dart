import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../core/widgets/text_style_sheet.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../../export/data/whatsapp_export_service.dart';
import '../domain/editor_bitmap.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/image_filters.dart';
import 'package:uuid/uuid.dart';

enum EditorTool { none, lasso, brush, eraser, text, transform }

final selectedToolProvider = StateProvider<EditorTool>(
  (ref) => EditorTool.none,
);
final brushSizeProvider = StateProvider<double>((ref) => 10.0);
final brushColorProvider = StateProvider<Color>((ref) => AppColors.coral);
final isProcessingProvider = StateProvider<bool>((ref) => false);

class EditorScreen extends ConsumerStatefulWidget {
  final String? imagePath;
  final String? targetPackId;
  final bool bulkMode;

  const EditorScreen({
    super.key,
    this.imagePath,
    this.targetPackId,
    this.bulkMode = false,
  });

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  img.Image? _editableImage;
  ui.Image? _loadedImage;
  _EditorSnapshot? _previousBgRemovalSnapshot;
  final List<_EditorSnapshot> _undoStack = [];
  List<Offset> _currentStroke = [];
  List<Offset> _currentSelectionPath = [];
  SelectionMask? _selectionMask;
  String? _overlayText;
  Offset _textPosition = const Offset(100, 100);
  bool _isTextSelected = false;
  bool _hasRemovedBg = false;
  bool _isCropping = false;
  bool _cropSquare = true;
  Rect? _cropRect;
  _CropDragHandle? _activeCropHandle;
  Offset? _lastCropImagePosition;
  String _processingLabel = 'Working...';

  // Text styling state
  StickerTextStyle _textStyle = const StickerTextStyle();

  @override
  void initState() {
    super.initState();
    if (widget.imagePath != null) {
      _loadImage();
    } else if (!widget.bulkMode) {
      // Auto-open image picker when no image is provided (not in bulk mode)
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      // User cancelled — stay on editor, they can tap the placeholder to retry
      return;
    }

    try {
      final bytes = await picked.readAsBytes();
      if (kDebugMode) {
        debugPrint(
          'Editor picked image path=${picked.path} mime=${picked.mimeType} '
          'bytes=${bytes.length}',
        );
      }
      await _loadImageBytes(bytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load picked image: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Couldn\'t open that photo. Try another one.'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadImage() async {
    final path = widget.imagePath;
    if (path == null) return;

    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Image file not found'),
              backgroundColor: AppColors.coral,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();
      await _loadImageBytes(bytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load image from path "$path": $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Couldn\'t open that image. Try another one.'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadImageBytes(Uint8List bytes) async {
    final decoded = await _decodeEditorImage(bytes);
    if (!mounted) {
      return;
    }

    setState(() {
      _editableImage = decoded.bitmap;
      _loadedImage = decoded.uiImage;
      _previousBgRemovalSnapshot = null;
      _undoStack.clear();
      _currentStroke = [];
      _currentSelectionPath = [];
      _selectionMask = null;
      _overlayText = null;
      _textStyle = const StickerTextStyle();
      _textPosition = _defaultTextPositionForImage(decoded.bitmap);
      _isTextSelected = false;
      _hasRemovedBg = false;
      _resetCropState();
    });
  }

  Future<void> _replaceEditableImage(
    img.Image bitmap, {
    bool clearSelection = false,
    bool resetCrop = false,
    Offset? textPosition,
  }) async {
    final normalized =
        bitmap.numChannels == 4
            ? img.Image.from(bitmap)
            : bitmap.convert(numChannels: 4);
    final uiImage = await _bitmapToUiImage(normalized);
    if (!mounted) {
      return;
    }

    setState(() {
      _editableImage = normalized;
      _loadedImage = uiImage;
      if (clearSelection) {
        _clearSelectionState();
      }
      if (resetCrop) {
        _resetCropState();
      }
      if (textPosition != null) {
        _textPosition = textPosition;
      }
    });
  }

  Future<ui.Image> _bitmapToUiImage(img.Image bitmap) async {
    // The raw RGBA path rendered as solid black on the Android photo picker
    // import flow. Going through a standard PNG codec is slower, but reliable
    // across platforms for editor previews.
    final encodedBytes = Uint8List.fromList(img.encodePng(bitmap));
    final buffer = await ui.ImmutableBuffer.fromUint8List(encodedBytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<_DecodedEditorImage> _decodeEditorImage(Uint8List bytes) async {
    try {
      final uiImage = await _decodeUiImage(bytes);
      final pixelData =
          await uiImage.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ) ??
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixelData == null) {
        throw Exception('Unable to extract image pixels');
      }

      final pixels = Uint8List.fromList(
        pixelData.buffer.asUint8List(
          pixelData.offsetInBytes,
          pixelData.lengthInBytes,
        ),
      );
      final bitmap = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      if (kDebugMode) {
        final sample = bitmap.getPixel(bitmap.width ~/ 2, bitmap.height ~/ 2);
        debugPrint(
          'Editor UI decode ${bitmap.width}x${bitmap.height} '
          'center=${sample.r.toInt()},${sample.g.toInt()},${sample.b.toInt()},${sample.a.toInt()}',
        );
      }
      return _DecodedEditorImage(bitmap: bitmap, uiImage: uiImage);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Editor UI decode failed, falling back to package:image: $error',
        );
      }
      final fallback = img.decodeImage(bytes);
      if (fallback == null) {
        throw Exception('Unsupported image format');
      }
      final normalized = fallback.convert(numChannels: 4);
      final uiImage = await _bitmapToUiImage(normalized);
      return _DecodedEditorImage(bitmap: normalized, uiImage: uiImage);
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  void _pushUndoSnapshot() {
    final snapshot = _captureSnapshot();
    if (snapshot == null) {
      return;
    }
    if (_undoStack.length >= 20) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(snapshot);
  }

  _EditorSnapshot? _captureSnapshot() {
    final bitmap = _editableImage;
    if (bitmap == null) {
      return null;
    }

    return _EditorSnapshot(
      bitmap: img.Image.from(bitmap),
      overlayText: _overlayText,
      textPosition: _textPosition,
      textStyle: _textStyle,
      hasRemovedBg: _hasRemovedBg,
      selectionMask: _copySelectionMask(_selectionMask),
    );
  }

  Future<void> _restoreSnapshot(_EditorSnapshot snapshot) async {
    final uiImage = await _bitmapToUiImage(snapshot.bitmap);
    if (!mounted) {
      return;
    }

    setState(() {
      _editableImage = img.Image.from(snapshot.bitmap);
      _loadedImage = uiImage;
      _overlayText = snapshot.overlayText;
      _textPosition = snapshot.textPosition;
      _textStyle = snapshot.textStyle;
      _hasRemovedBg = snapshot.hasRemovedBg;
      _selectionMask = _copySelectionMask(snapshot.selectionMask);
      _currentStroke = [];
      _currentSelectionPath = [];
      _isTextSelected = false;
      _resetCropState();
    });
  }

  Future<void> _undoLastEdit() async {
    if (_undoStack.isEmpty) {
      return;
    }
    final snapshot = _undoStack.removeLast();
    await _restoreSnapshot(snapshot);
  }

  SelectionMask? _copySelectionMask(SelectionMask? mask) {
    if (mask == null) {
      return null;
    }
    return SelectionMask(
      width: mask.width,
      height: mask.height,
      values: Uint8List.fromList(mask.values),
      bounds: mask.bounds,
      polygon: List<Offset>.from(mask.polygon),
    );
  }

  Offset _defaultTextPositionForImage(img.Image image) {
    return Offset(image.width * 0.12, image.height * 0.74);
  }

  Offset _clampTextPosition(Offset position, img.Image image) {
    final maxX = image.width > 32 ? image.width - 32.0 : 0.0;
    final maxY = image.height > 32 ? image.height - 32.0 : 0.0;
    return Offset(
      position.dx.clamp(0.0, maxX).toDouble(),
      position.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  void _clearSelectionState() {
    _selectionMask = null;
    _currentSelectionPath = [];
  }

  void _resetCropState() {
    _isCropping = false;
    _cropRect = null;
    _activeCropHandle = null;
    _lastCropImagePosition = null;
  }

  void _showBgRemovalSheet() {
    if (_editableImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No image loaded to remove background from'),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    double tolerance = 40;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSheetState) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Background Removal',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      // Primary: AI-powered (server-side RMBG-2.0)
                      BubblyButton(
                        label: 'AI Remove Background',
                        icon: Icons.auto_awesome_rounded,
                        gradient: AppColors.primaryGradient,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _removeBackgroundAI();
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Best quality — uses AI on our servers',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'or use quick remove (works offline)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Low',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: tolerance,
                              min: 10,
                              max: 100,
                              divisions: 18,
                              activeColor: AppColors.purple,
                              label: '${tolerance.round()}',
                              onChanged:
                                  (v) => setSheetState(() => tolerance = v),
                            ),
                          ),
                          const Text(
                            'High',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      BubblyButton(
                        label: 'Quick Remove',
                        icon: Icons.auto_fix_high_rounded,
                        color: AppColors.textSecondary,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _removeBackground(tolerance: tolerance.round());
                        },
                      ),
                      if (_hasRemovedBg &&
                          _previousBgRemovalSnapshot != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _undoBgRemoval();
                          },
                          child: const Text('Undo Previous Removal'),
                        ),
                      ],
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _undoBgRemoval() async {
    final snapshot = _previousBgRemovalSnapshot;
    if (snapshot == null) {
      return;
    }
    _previousBgRemovalSnapshot = null;
    await _restoreSnapshot(snapshot);
    if (!mounted) {
      return;
    }
    setState(() => _hasRemovedBg = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Background removal undone'),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _removeBackground({int tolerance = 40}) async {
    final bitmap = _editableImage;
    if (bitmap == null) {
      return;
    }

    setState(() => _processingLabel = 'Removing background...');
    ref.read(isProcessingProvider.notifier).state = true;
    HapticFeedback.mediumImpact();

    try {
      await Future<void>.delayed(Duration.zero);
      _previousBgRemovalSnapshot = _captureSnapshot();
      _pushUndoSnapshot();

      final result = await compute(
        _removeBackgroundIsolate,
        _BackgroundRemovalParams(
          rgbaBytes: bitmap.getBytes(order: img.ChannelOrder.rgba),
          width: bitmap.width,
          height: bitmap.height,
          tolerance: tolerance,
        ),
      );

      final updatedBitmap = img.Image.fromBytes(
        width: bitmap.width,
        height: bitmap.height,
        bytes: result.pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      await _replaceEditableImage(updatedBitmap);

      if (!mounted) {
        return;
      }

      setState(() => _hasRemovedBg = result.removedPixels > 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.removedPixels > 0
                ? 'Background removed!'
                : 'Could not isolate the background. Try lasso or crop.',
          ),
          backgroundColor:
              result.removedPixels > 0 ? AppColors.success : AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Background removal failed: $e'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      ref.read(isProcessingProvider.notifier).state = false;
    }
  }

  Future<void> _removeBackgroundAI() async {
    final bitmap = _editableImage;
    if (bitmap == null) return;

    setState(() => _processingLabel = 'AI removing background...');
    ref.read(isProcessingProvider.notifier).state = true;
    HapticFeedback.mediumImpact();

    try {
      await Future<void>.delayed(Duration.zero);
      _previousBgRemovalSnapshot = _captureSnapshot();
      _pushUndoSnapshot();

      // Resize if too large (max 1024px on longest side) to reduce upload
      var sendBitmap = bitmap;
      if (bitmap.width > 1024 || bitmap.height > 1024) {
        final scale =
            1024 /
            (bitmap.width > bitmap.height ? bitmap.width : bitmap.height);
        sendBitmap = img.copyResize(
          bitmap,
          width: (bitmap.width * scale).round(),
          height: (bitmap.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      // Encode to PNG
      final pngBytes = Uint8List.fromList(img.encodePng(sendBitmap));

      // Call server-side RMBG-2.0
      final apiClient = ref.read(apiClientProvider);
      final resultBytes = await apiClient.removeBackground(pngBytes);

      if (resultBytes == null) {
        throw Exception('Server returned no result — try Quick Remove instead');
      }

      // Decode the result PNG
      var resultImage = img.decodePng(resultBytes);
      if (resultImage == null) {
        throw Exception('Failed to decode result image');
      }

      // Resize back to original dimensions if we downscaled
      if (resultImage.width != bitmap.width ||
          resultImage.height != bitmap.height) {
        resultImage = img.copyResize(
          resultImage,
          width: bitmap.width,
          height: bitmap.height,
          interpolation: img.Interpolation.linear,
        );
      }

      await _replaceEditableImage(resultImage);

      if (!mounted) return;

      setState(() => _hasRemovedBg = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Background removed with AI!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI removal failed: ${e.toString().split('\n').first}. '
              'Try Quick Remove for offline use.',
            ),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      ref.read(isProcessingProvider.notifier).state = false;
    }
  }

  Future<void> _cropImage() async {
    final bitmap = _editableImage;
    if (bitmap == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No image loaded to crop'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    if (_isCropping) {
      await _applyCrop();
      return;
    }

    setState(() {
      _isCropping = true;
      _cropRect = _selectionMask?.bounds ?? _defaultCropRect(bitmap);
      _cropSquare = _selectionMask == null;
      _isTextSelected = false;
    });
  }

  Rect _defaultCropRect(img.Image image) {
    final insetX = image.width * 0.08;
    final insetY = image.height * 0.08;
    final width = image.width - insetX * 2;
    final height = image.height - insetY * 2;
    final side = width < height ? width : height;
    return Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side,
      side,
    );
  }

  Rect _normalizeCropRect(Rect rect, img.Image image) {
    const minSize = 48.0;
    final maxLeft =
        (image.width - minSize).clamp(0.0, image.width.toDouble()).toDouble();
    final maxTop =
        (image.height - minSize).clamp(0.0, image.height.toDouble()).toDouble();
    var left = rect.left.clamp(0.0, maxLeft).toDouble();
    var top = rect.top.clamp(0.0, maxTop).toDouble();
    var right =
        rect.right.clamp(left + minSize, image.width.toDouble()).toDouble();
    var bottom =
        rect.bottom.clamp(top + minSize, image.height.toDouble()).toDouble();

    if (right - left < minSize) {
      right =
          (left + minSize).clamp(minSize, image.width.toDouble()).toDouble();
      left = (right - minSize).clamp(0.0, maxLeft).toDouble();
    }
    if (bottom - top < minSize) {
      bottom =
          (top + minSize).clamp(minSize, image.height.toDouble()).toDouble();
      top = (bottom - minSize).clamp(0.0, maxTop).toDouble();
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _clampedImagePosition(CanvasPointerData data) {
    final bitmap = _editableImage!;
    if (data.imagePosition != null) {
      return data.imagePosition!;
    }
    return Offset(
      ((data.canvasPosition.dx - data.imageRect.left) /
              data.imageRect.width *
              bitmap.width)
          .clamp(0.0, bitmap.width - 1.0)
          .toDouble(),
      ((data.canvasPosition.dy - data.imageRect.top) /
              data.imageRect.height *
              bitmap.height)
          .clamp(0.0, bitmap.height - 1.0)
          .toDouble(),
    );
  }

  _CropDragHandle? _hitTestCropHandle(CanvasPointerData data) {
    final bitmap = _editableImage;
    final cropRect = _cropRect;
    if (bitmap == null || cropRect == null) {
      return null;
    }

    final canvasRect = Rect.fromLTWH(
      data.imageRect.left + cropRect.left * data.imageRect.width / bitmap.width,
      data.imageRect.top + cropRect.top * data.imageRect.height / bitmap.height,
      cropRect.width * data.imageRect.width / bitmap.width,
      cropRect.height * data.imageRect.height / bitmap.height,
    );
    const threshold = 22.0;

    bool near(Offset handle) =>
        (data.canvasPosition - handle).distanceSquared <= threshold * threshold;

    if (near(canvasRect.topLeft)) {
      return _CropDragHandle.topLeft;
    }
    if (near(canvasRect.topRight)) {
      return _CropDragHandle.topRight;
    }
    if (near(canvasRect.bottomLeft)) {
      return _CropDragHandle.bottomLeft;
    }
    if (near(canvasRect.bottomRight)) {
      return _CropDragHandle.bottomRight;
    }
    if (canvasRect.inflate(8).contains(data.canvasPosition)) {
      return _CropDragHandle.move;
    }
    return null;
  }

  void _handleCropStart(CanvasPointerData data) {
    setState(() {
      _activeCropHandle = _hitTestCropHandle(data);
      _lastCropImagePosition = _clampedImagePosition(data);
    });
  }

  void _handleCropUpdate(CanvasPointerData data) {
    final bitmap = _editableImage;
    final cropRect = _cropRect;
    final activeHandle = _activeCropHandle;
    final previousPosition = _lastCropImagePosition;
    if (bitmap == null ||
        cropRect == null ||
        activeHandle == null ||
        previousPosition == null) {
      return;
    }

    final currentPosition = _clampedImagePosition(data);
    Rect nextRect;
    if (activeHandle == _CropDragHandle.move) {
      final delta = currentPosition - previousPosition;
      nextRect = _normalizeCropRect(cropRect.shift(delta), bitmap);
      final dx =
          nextRect.right > bitmap.width
              ? bitmap.width - nextRect.right
              : nextRect.left < 0
              ? -nextRect.left
              : 0.0;
      final dy =
          nextRect.bottom > bitmap.height
              ? bitmap.height - nextRect.bottom
              : nextRect.top < 0
              ? -nextRect.top
              : 0.0;
      nextRect = nextRect.shift(Offset(dx, dy));
    } else {
      nextRect = _resizeCropRect(
        cropRect,
        activeHandle,
        currentPosition,
        bitmap,
      );
    }

    setState(() {
      _cropRect = nextRect;
      _lastCropImagePosition = currentPosition;
    });
  }

  Rect _resizeCropRect(
    Rect rect,
    _CropDragHandle handle,
    Offset cursor,
    img.Image image,
  ) {
    const minSize = 48.0;
    final anchor = switch (handle) {
      _CropDragHandle.topLeft => rect.bottomRight,
      _CropDragHandle.topRight => rect.bottomLeft,
      _CropDragHandle.bottomLeft => rect.topRight,
      _CropDragHandle.bottomRight => rect.topLeft,
      _CropDragHandle.move => rect.topLeft,
    };

    if (_cropSquare && handle != _CropDragHandle.move) {
      final dx = cursor.dx - anchor.dx;
      final dy = cursor.dy - anchor.dy;
      final side = (dx.abs() > dy.abs() ? dx.abs() : dy.abs()).clamp(
        minSize,
        image.width > image.height
            ? image.height.toDouble()
            : image.width.toDouble(),
      );
      final horizontalSign = dx >= 0 ? 1.0 : -1.0;
      final verticalSign = dy >= 0 ? 1.0 : -1.0;
      final corner = Offset(
        anchor.dx + side * horizontalSign,
        anchor.dy + side * verticalSign,
      );
      return _normalizeCropRect(Rect.fromPoints(anchor, corner), image);
    }

    final nextRect = switch (handle) {
      _CropDragHandle.topLeft => Rect.fromLTRB(
        cursor.dx,
        cursor.dy,
        rect.right,
        rect.bottom,
      ),
      _CropDragHandle.topRight => Rect.fromLTRB(
        rect.left,
        cursor.dy,
        cursor.dx,
        rect.bottom,
      ),
      _CropDragHandle.bottomLeft => Rect.fromLTRB(
        cursor.dx,
        rect.top,
        rect.right,
        cursor.dy,
      ),
      _CropDragHandle.bottomRight => Rect.fromLTRB(
        rect.left,
        rect.top,
        cursor.dx,
        cursor.dy,
      ),
      _CropDragHandle.move => rect,
    };
    return _normalizeCropRect(nextRect, image);
  }

  void _handleCropEnd() {
    setState(() {
      _activeCropHandle = null;
      _lastCropImagePosition = null;
    });
  }

  Future<void> _applyCrop() async {
    final bitmap = _editableImage;
    final cropRect = _cropRect;
    if (bitmap == null || cropRect == null) {
      return;
    }

    _pushUndoSnapshot();
    final normalizedCrop = _normalizeCropRect(cropRect, bitmap);
    final cropped = cropBitmap(bitmap, normalizedCrop);
    final nextTextPosition =
        _overlayText == null
            ? _textPosition
            : _clampTextPosition(
              _textPosition - normalizedCrop.topLeft,
              cropped,
            );

    await _replaceEditableImage(
      cropped,
      clearSelection: true,
      resetCrop: true,
      textPosition: nextTextPosition,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Image cropped!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _cancelCropMode() {
    setState(() => _resetCropState());
  }

  img.Color _brushImageColor() {
    final color = ref.read(brushColorProvider);
    return img.ColorRgba8(
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
      (color.a * 255).round(),
    );
  }

  void _handleCanvasPanStart(CanvasPointerData data, EditorTool tool) {
    if (_isCropping) {
      _handleCropStart(data);
      return;
    }

    if (_editableImage == null) {
      return;
    }

    final imagePosition = _clampedImagePosition(data);
    if (tool == EditorTool.brush || tool == EditorTool.eraser) {
      setState(() {
        _currentStroke = [imagePosition];
        _isTextSelected = false;
      });
      return;
    }

    if (tool == EditorTool.lasso) {
      setState(() {
        _currentSelectionPath = [imagePosition];
        _isTextSelected = false;
      });
    }
  }

  void _handleCanvasPanUpdate(CanvasPointerData data, EditorTool tool) {
    if (_isCropping) {
      _handleCropUpdate(data);
      return;
    }

    if (_editableImage == null) {
      return;
    }

    final imagePosition = _clampedImagePosition(data);
    if ((tool == EditorTool.brush || tool == EditorTool.eraser) &&
        _currentStroke.isNotEmpty) {
      setState(() => _currentStroke = [..._currentStroke, imagePosition]);
      return;
    }

    if (tool == EditorTool.lasso && _currentSelectionPath.isNotEmpty) {
      setState(
        () => _currentSelectionPath = [..._currentSelectionPath, imagePosition],
      );
    }
  }

  void _handleCanvasPanEnd(EditorTool tool) {
    if (_isCropping) {
      _handleCropEnd();
      return;
    }

    if (tool == EditorTool.brush || tool == EditorTool.eraser) {
      unawaited(_finishCurrentStroke(tool));
      return;
    }

    if (tool == EditorTool.lasso) {
      _finalizeSelection();
    }
  }

  Future<void> _finishCurrentStroke(EditorTool tool) async {
    final bitmap = _editableImage;
    if (bitmap == null || _currentStroke.isEmpty) {
      return;
    }

    final strokePoints = List<Offset>.from(_currentStroke);
    setState(() => _currentStroke = []);
    _pushUndoSnapshot();
    final updated = applyStrokeToBitmap(
      source: bitmap,
      points: strokePoints,
      size: ref.read(brushSizeProvider),
      color: _brushImageColor(),
      erase: tool == EditorTool.eraser,
      selectionMask: _selectionMask,
    );
    await _replaceEditableImage(updated);
  }

  void _finalizeSelection() {
    final bitmap = _editableImage;
    if (bitmap == null) {
      return;
    }

    if (_currentSelectionPath.length < 3) {
      setState(() => _currentSelectionPath = []);
      return;
    }

    final mask = buildSelectionMask(
      width: bitmap.width,
      height: bitmap.height,
      polygon: _currentSelectionPath,
    );
    if (mask == null || mask.isEmpty) {
      setState(() => _currentSelectionPath = []);
      return;
    }

    setState(() {
      _selectionMask = mask;
      _currentSelectionPath = [];
      _isTextSelected = false;
    });
  }

  Future<void> _eraseSelectedArea() async {
    final bitmap = _editableImage;
    final selectionMask = _selectionMask;
    if (bitmap == null || selectionMask == null) {
      return;
    }
    _pushUndoSnapshot();
    await _replaceEditableImage(
      eraseSelection(bitmap, selectionMask),
      clearSelection: true,
    );
  }

  Future<void> _keepOnlySelectedArea() async {
    final bitmap = _editableImage;
    final selectionMask = _selectionMask;
    if (bitmap == null || selectionMask == null) {
      return;
    }
    _pushUndoSnapshot();
    await _replaceEditableImage(
      keepSelection(bitmap, selectionMask),
      clearSelection: true,
    );
  }

  void _cropToSelection() {
    final selectionMask = _selectionMask;
    if (selectionMask == null) {
      return;
    }
    setState(() {
      _isCropping = true;
      _cropRect = selectionMask.bounds;
      _cropSquare = false;
    });
  }

  void _addText() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Text'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type your text...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = StickerGuardrails.sanitizeText(controller.text);
                Navigator.pop(ctx);
                if (text.isNotEmpty) {
                  if (!StickerGuardrails.isKidSafeText(text)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Oops! Please use friendly words only.',
                        ),
                        backgroundColor: AppColors.coral,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                    return;
                  }
                  _showTextStyleSheet(text);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showTextStyleSheet(String text) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return TextStyleBottomSheet(
          text: text,
          initialStyle: _textStyle,
          onApply: (style) {
            setState(() {
              if (_overlayText == null && _editableImage != null) {
                _textPosition = _defaultTextPositionForImage(_editableImage!);
              }
              _overlayText = text;
              _textStyle = style;
            });
          },
        );
      },
    );
  }

  Future<void> _showFilterSheet() async {
    final bitmap = _editableImage;
    if (bitmap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Load an image first to apply styles'),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _processingLabel = 'Loading styles...');
    ref.read(isProcessingProvider.notifier).state = true;

    try {
      final pngBytes = Uint8List.fromList(img.encodePng(bitmap));

      // Create tiny thumbnail for fast preview generation
      final thumb = img.copyResize(bitmap, width: 72, height: 72);

      final previews = <StickerFilter, Uint8List>{};
      for (final filter in StickerFilter.values) {
        final filtered = applyFilter(thumb.clone(), filter);
        previews[filter] = Uint8List.fromList(img.encodePng(filtered));
      }

      ref.read(isProcessingProvider.notifier).state = false;

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder:
            (ctx) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose a Style',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children:
                          StickerFilter.values.map((filter) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _applyFilter(filter, pngBytes);
                                },
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.memory(
                                        previews[filter]!,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      filter.label,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ],
              ),
            ),
      );
    } catch (e) {
      ref.read(isProcessingProvider.notifier).state = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load styles: $e'),
            backgroundColor: AppColors.coral,
          ),
        );
      }
    }
  }

  Future<void> _applyFilter(
    StickerFilter filter,
    Uint8List sourcePngBytes,
  ) async {
    if (filter == StickerFilter.none) return;
    setState(() => _processingLabel = 'Applying ${filter.label}...');
    ref.read(isProcessingProvider.notifier).state = true;
    try {
      _pushUndoSnapshot();
      final result = await compute(
        applyFilterIsolate,
        FilterParams(pngBytes: sourcePngBytes, filter: filter),
      );
      final decoded = img.decodePng(result);
      if (decoded == null) {
        throw Exception('Could not decode filtered image');
      }
      await _replaceEditableImage(decoded);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${filter.label} style applied!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Filter failed: $e'),
            backgroundColor: AppColors.coral,
          ),
        );
      }
    } finally {
      ref.read(isProcessingProvider.notifier).state = false;
    }
  }

  void _aiCaption() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI Caption Suggestions',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                ...['LOL 😂', 'Mood 💅', 'Not today 🙅', 'Send help 🆘'].map(
                  (caption) => ListTile(
                    title: Text(caption),
                    trailing: const Icon(Icons.add_rounded),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      setState(() {
                        if (_overlayText == null && _editableImage != null) {
                          _textPosition = _defaultTextPositionForImage(
                            _editableImage!,
                          );
                        }
                        _overlayText = caption;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  Future<String?> _captureCanvasToPng() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();

      // Compress to fit WhatsApp's 100KB static sticker limit
      final compressedBytes = await StickerGuardrails.compressStaticSticker(
        Uint8List.fromList(pngBytes),
      );

      final directory = await getApplicationDocumentsDirectory();
      final stickersDir = Directory('${directory.path}/stickers');
      if (!await stickersDir.exists()) {
        await stickersDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${stickersDir.path}/sticker_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(compressedBytes);

      return filePath;
    } catch (e) {
      debugPrint('Failed to capture canvas: $e');
      return null;
    }
  }

  Future<void> _showSaveToPackDialog(String stickerPath) async {
    final packsAsync = ref.read(packsProvider);
    final existingPacks = (packsAsync.valueOrNull ?? [])
        .where((pack) => pack.type == StickerPackType.staticPack)
        .toList(growable: false);
    final nameController = TextEditingController(text: 'My Stickers');

    // Pre-select target pack if passed from pack detail screen
    StickerPack? selectedExistingPack;
    bool createNew = existingPacks.isEmpty;
    if (widget.targetPackId != null && existingPacks.isNotEmpty) {
      final target =
          existingPacks.where((p) => p.id == widget.targetPackId).firstOrNull;
      if (target != null) {
        selectedExistingPack = target;
        createNew = false;
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Save to Pack'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existingPacks.isNotEmpty) ...[
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('New Pack'),
                          selected: createNew,
                          onSelected: (selected) {
                            setDialogState(() {
                              createNew = true;
                              selectedExistingPack = null;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Existing Pack'),
                          selected: !createNew,
                          onSelected: (selected) {
                            setDialogState(() {
                              createNew = false;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (createNew)
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Pack Name',
                        hintText: 'Enter pack name...',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    DropdownButtonFormField<StickerPack>(
                      decoration: const InputDecoration(
                        labelText: 'Select Pack',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedExistingPack,
                      items:
                          existingPacks
                              .map(
                                (pack) => DropdownMenuItem<StickerPack>(
                                  value: pack,
                                  child: Text(
                                    '${pack.name} (${pack.stickerPaths.length} stickers)',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (pack) {
                        setDialogState(() {
                          selectedExistingPack = pack;
                        });
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;

    if (createNew) {
      final packName =
          nameController.text.trim().isEmpty
              ? 'My Stickers'
              : nameController.text.trim();
      final newPack = StickerPack(
        id: const Uuid().v4(),
        name: packName,
        authorName: 'Me',
        type: StickerPackType.staticPack,
        stickerPaths: [stickerPath],
        createdAt: DateTime.now(),
      );
      await ref.read(packsProvider.notifier).addPack(newPack);
    } else if (selectedExistingPack != null) {
      if (selectedExistingPack!.stickerPaths.length >=
          StickerGuardrails.maxStickersPerPack) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'This pack already has ${StickerGuardrails.maxStickersPerPack} stickers — that\'s the max!',
              ),
              backgroundColor: AppColors.coral,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
      final updatedPack = selectedExistingPack!.copyWith(
        stickerPaths: [...selectedExistingPack!.stickerPaths, stickerPath],
      );
      await ref.read(packsProvider.notifier).updatePack(updatedPack);
    } else {
      // No pack selected — do nothing
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No pack selected'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      _showAddAnotherDialog();
    }
  }

  /// After saving a sticker, offer to create another one for the same pack.
  void _showAddAnotherDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Sticker Saved!'),
          content: const Text('Want to create another sticker for this pack?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) context.pop(); // Go back to home
              },
              child: const Text('Done'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
              onPressed: () {
                Navigator.pop(ctx);
                // Reset canvas for a new sticker
                setState(() {
                  _editableImage = null;
                  _loadedImage = null;
                  _undoStack.clear();
                  _previousBgRemovalSnapshot = null;
                  _currentStroke = [];
                  _currentSelectionPath = [];
                  _selectionMask = null;
                  _overlayText = null;
                  _textPosition = const Offset(100, 100);
                  _hasRemovedBg = false;
                  _textStyle = const StickerTextStyle();
                  _isTextSelected = false;
                  _resetCropState();
                });
              },
              child: const Text('Create Another!'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportLatestPackToWhatsApp() async {
    final packs = ref.read(packsProvider).valueOrNull ?? [];
    if (packs.isEmpty) return;

    // The most recently modified pack (the one we just saved to)
    final pack = packs.first;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Preparing stickers for WhatsApp...'),
        backgroundColor: AppColors.whatsappGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    final exportService = WhatsAppExportService();
    final stickerDataList = <StickerData>[];

    for (final path in pack.stickerPaths) {
      final file = File(path);
      if (await file.exists()) {
        stickerDataList.add(
          StickerData(
            data: await file.readAsBytes(),
            isAnimated: pack.type.isAnimated,
            sourcePath: path,
          ),
        );
      }
    }

    while (stickerDataList.length < WhatsAppExportService.minStickersPerPack) {
      stickerDataList.add(
        StickerData(
          data: WhatsAppExportService.generatePlaceholderSticker(),
          isAnimated: pack.type.isAnimated,
        ),
      );
    }

    Uint8List trayIcon;
    if (pack.trayIconPath != null && await File(pack.trayIconPath!).exists()) {
      trayIcon = await File(pack.trayIconPath!).readAsBytes();
    } else {
      trayIcon = stickerDataList.first.data;
    }

    final result = await exportService.exportToWhatsApp(
      packName: pack.name,
      packAuthor: pack.authorName,
      stickers: stickerDataList,
      trayIcon: trayIcon,
      trayIconSourcePath: pack.trayIconPath,
      packIdentifier: pack.id,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? AppColors.whatsappGreen : AppColors.coral,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveBulkAndPop() async {
    final savedPath = await _captureCanvasToPng();
    if (!mounted) return;
    Navigator.pop(context, savedPath);
  }

  void _saveSticker() {
    if (widget.bulkMode) {
      _saveBulkAndPop();
      return;
    }
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Save Sticker',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                BubblyButton(
                  label: 'Save to Pack',
                  icon: Icons.folder_rounded,
                  color: AppColors.coral,
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final savedPath = await _captureCanvasToPng();
                    if (!mounted) return;
                    if (savedPath != null) {
                      await _showSaveToPackDialog(savedPath);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Failed to save sticker'),
                          backgroundColor: AppColors.coral,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                BubblyButton(
                  label: 'Add to WhatsApp',
                  icon: Icons.chat_rounded,
                  color: AppColors.whatsappGreen,
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final savedPath = await _captureCanvasToPng();
                    if (!mounted) return;
                    if (savedPath != null) {
                      await _showSaveToPackDialog(savedPath);
                      if (!mounted) return;
                      // After saving, trigger WhatsApp export for the most recent pack
                      await _exportLatestPackToWhatsApp();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Failed to save sticker'),
                          backgroundColor: AppColors.coral,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTool = ref.watch(selectedToolProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final hasSelection = _selectionMask != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _isCropping ? Icons.close_fullscreen_rounded : Icons.close_rounded,
          ),
          tooltip: _isCropping ? 'Cancel Crop' : 'Close Editor',
          onPressed:
              _isCropping
                  ? _cancelCropMode
                  : widget.bulkMode
                  ? () => Navigator.pop(context, null)
                  : () => context.pop(),
        ),
        title: const Text('Sticker Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo',
            onPressed: _undoStack.isNotEmpty ? () => _undoLastEdit() : null,
          ),
          IconButton(
            icon: const Icon(Icons.crop_rounded),
            tooltip: 'Crop Sticker',
            onPressed: _cropImage,
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: widget.bulkMode ? 'Save & Next' : 'Save Sticker',
            onPressed: _isCropping ? null : _saveSticker,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Canvas area
              Expanded(
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: EditorCanvas(
                    image: _loadedImage,
                    strokes: const [],
                    currentStroke: _currentStroke,
                    currentSelectionPath: _currentSelectionPath,
                    currentStrokeIsEraser: selectedTool == EditorTool.eraser,
                    currentStrokeColor: ref.watch(brushColorProvider),
                    currentStrokeSize: ref.watch(brushSizeProvider),
                    overlayText: _overlayText,
                    textPosition: _textPosition,
                    textStyle: _textStyle,
                    isTextSelected: _isTextSelected,
                    hasRemovedBg: _hasRemovedBg,
                    selectedTool: selectedTool,
                    selectionPolygon: _selectionMask?.polygon ?? const [],
                    cropRect: _cropRect,
                    isCropping: _isCropping,
                    onTapPlaceholder: _pickImage,
                    onCanvasTap: () {
                      if (_isTextSelected) {
                        setState(() => _isTextSelected = false);
                      }
                    },
                    onTextTap: () {
                      setState(() => _isTextSelected = true);
                      ref.read(selectedToolProvider.notifier).state =
                          EditorTool.transform;
                    },
                    onTextDrag: (newPos) {
                      setState(() {
                        _textPosition =
                            _editableImage == null
                                ? newPos
                                : _clampTextPosition(newPos, _editableImage!);
                      });
                    },
                    onPanStart:
                        (data) => _handleCanvasPanStart(data, selectedTool),
                    onPanUpdate:
                        (data) => _handleCanvasPanUpdate(data, selectedTool),
                    onPanEnd: () => _handleCanvasPanEnd(selectedTool),
                  ),
                ),
              ),
              if (_isCropping) _buildCropControls(),
              if (!_isCropping && hasSelection) _buildSelectionActionBar(),
              // Tool options row (size slider + color picker)
              if (!_isCropping &&
                  (selectedTool == EditorTool.brush ||
                      selectedTool == EditorTool.eraser))
                _buildToolOptionsRow(selectedTool),
              // Toolbar
              if (!_isCropping)
                EditorToolbar(
                  selectedTool: selectedTool,
                  onToolSelected: (tool) {
                    HapticFeedback.selectionClick();
                    ref.read(selectedToolProvider.notifier).state = tool;
                  },
                  onRemoveBg: _showBgRemovalSheet,
                  onAddText: _addText,
                  onAiStyle: _showFilterSheet,
                  onAiCaption: _aiCaption,
                ),
            ],
          ),
          // Processing overlay
          if (isProcessing)
            Container(
              color: Colors.black38,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.coral),
                      const SizedBox(height: 16),
                      Text(_processingLabel),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _keepOnlySelectedArea,
            icon: const Icon(Icons.center_focus_strong_rounded),
            label: const Text('Keep'),
          ),
          FilledButton.icon(
            onPressed: _eraseSelectedArea,
            icon: const Icon(Icons.auto_fix_off_rounded),
            label: const Text('Erase'),
          ),
          FilledButton.icon(
            onPressed: _cropToSelection,
            icon: const Icon(Icons.crop_free_rounded),
            label: const Text('Crop'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(_clearSelectionState),
            icon: const Icon(Icons.clear_rounded),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildCropControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _cancelCropMode,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => setState(() => _cropSquare = !_cropSquare),
              icon: Icon(
                _cropSquare
                    ? Icons.crop_square_rounded
                    : Icons.crop_free_rounded,
              ),
              label: Text(_cropSquare ? 'Square' : 'Free'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _applyCrop,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolOptionsRow(EditorTool tool) {
    final brushSize = ref.watch(brushSizeProvider);
    final brushColor = ref.watch(brushColorProvider);
    const colors = [
      AppColors.coral,
      Colors.black,
      Colors.white,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.pink,
      AppColors.purple,
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Size slider
            Row(
              children: [
                const Icon(
                  Icons.circle,
                  size: 8,
                  color: AppColors.textSecondary,
                ),
                Expanded(
                  child: Slider(
                    value: brushSize,
                    min: 2,
                    max: 30,
                    divisions: 28,
                    activeColor:
                        tool == EditorTool.eraser ? Colors.orange : brushColor,
                    label: '${brushSize.round()}px',
                    onChanged:
                        (v) => ref.read(brushSizeProvider.notifier).state = v,
                  ),
                ),
                const Icon(
                  Icons.circle,
                  size: 24,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${brushSize.round()}px',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            // Color picker (only for brush, not eraser)
            if (tool == EditorTool.brush)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children:
                      colors.map((color) {
                        final isSelected =
                            brushColor.toARGB32() == color.toARGB32();
                        return GestureDetector(
                          onTap:
                              () =>
                                  ref.read(brushColorProvider.notifier).state =
                                      color,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected
                                        ? AppColors.coral
                                        : Colors.grey.shade400,
                                width: isSelected ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Editor types for undo/redo and crop
// =============================================================================

class _EditorSnapshot {
  final img.Image bitmap;
  final String? overlayText;
  final Offset textPosition;
  final StickerTextStyle textStyle;
  final bool hasRemovedBg;
  final SelectionMask? selectionMask;

  const _EditorSnapshot({
    required this.bitmap,
    this.overlayText,
    required this.textPosition,
    required this.textStyle,
    required this.hasRemovedBg,
    this.selectionMask,
  });
}

class _DecodedEditorImage {
  final img.Image bitmap;
  final ui.Image uiImage;

  const _DecodedEditorImage({required this.bitmap, required this.uiImage});
}

enum _CropDragHandle { topLeft, topRight, bottomLeft, bottomRight, move }

class _BackgroundRemovalParams {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final int tolerance;
  const _BackgroundRemovalParams({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.tolerance,
  });
}

class _BackgroundRemovalResult {
  final Uint8List pixels;
  final int removedPixels;
  const _BackgroundRemovalResult({
    required this.pixels,
    required this.removedPixels,
  });
}

_BackgroundRemovalResult _removeBackgroundIsolate(
  _BackgroundRemovalParams params,
) {
  final source = img.Image.fromBytes(
    width: params.width,
    height: params.height,
    bytes: params.rgbaBytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final result = removeBackgroundFromEdges(source, tolerance: params.tolerance);
  return _BackgroundRemovalResult(
    pixels: result.image.getBytes(order: img.ChannelOrder.rgba),
    removedPixels: result.removedPixels,
  );
}
