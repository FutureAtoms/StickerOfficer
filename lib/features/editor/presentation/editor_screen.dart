import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/editor_toolbar.dart';

enum EditorTool { none, lasso, brush, eraser, text, transform }

final selectedToolProvider = StateProvider<EditorTool>(
  (ref) => EditorTool.none,
);
final brushSizeProvider = StateProvider<double>((ref) => 10.0);
final isProcessingProvider = StateProvider<bool>((ref) => false);

class EditorScreen extends ConsumerStatefulWidget {
  final String? imagePath;

  const EditorScreen({super.key, this.imagePath});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  ui.Image? _loadedImage;
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String? _overlayText;
  Offset _textPosition = const Offset(100, 100);
  bool _hasRemovedbg = false;

  @override
  void initState() {
    super.initState();
    if (widget.imagePath != null) {
      _loadImage();
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
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _loadedImage = frameInfo.image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load image: $e'),
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

  Future<void> _removeBackground() async {
    if (_loadedImage == null) {
      if (mounted) {
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
      }
      return;
    }

    ref.read(isProcessingProvider.notifier).state = true;
    HapticFeedback.mediumImpact();

    try {
      // Convert ui.Image to raw RGBA bytes
      final byteData = await _loadedImage!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) throw Exception('Failed to read image data');

      final width = _loadedImage!.width;
      final height = _loadedImage!.height;
      final pixels = byteData.buffer.asUint8List();

      // Use the image package for flood-fill background removal
      final result = await _floodFillRemoveBackground(pixels, width, height);

      // Convert back to ui.Image
      final completer = ui.ImmutableBuffer.fromUint8List(result);
      final buffer = await completer;
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frameInfo = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _loadedImage = frameInfo.image;
          _hasRemovedbg = true;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Background removed!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
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

  /// Simple flood-fill background removal from corners.
  /// Marks pixels as transparent if they are similar in color to the corner
  /// pixels, spreading inward using a queue-based flood fill.
  Future<Uint8List> _floodFillRemoveBackground(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    final result = Uint8List.fromList(pixels);
    final visited = List<bool>.filled(width * height, false);
    const tolerance = 40; // Color similarity tolerance (0-255 per channel)

    int pixelIndex(int x, int y) => (y * width + x) * 4;

    bool isSimilar(int idx1, int idx2) {
      final dr = (result[idx1] - result[idx2]).abs();
      final dg = (result[idx1 + 1] - result[idx2 + 1]).abs();
      final db = (result[idx1 + 2] - result[idx2 + 2]).abs();
      return dr < tolerance && dg < tolerance && db < tolerance;
    }

    void floodFill(int startX, int startY) {
      final refIdx = pixelIndex(startX, startY);
      // Skip if the starting pixel is already transparent
      if (result[refIdx + 3] == 0) return;

      final queue = <int>[];
      final startLinear = startY * width + startX;
      queue.add(startLinear);
      visited[startLinear] = true;

      while (queue.isNotEmpty) {
        final linear = queue.removeLast();
        final x = linear % width;
        final y = linear ~/ width;
        final idx = linear * 4;

        // Make transparent
        result[idx + 3] = 0;

        // Check 4 neighbors
        for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final nLinear = ny * width + nx;
          if (visited[nLinear]) continue;
          visited[nLinear] = true;
          final nIdx = nLinear * 4;
          if (isSimilar(nIdx, refIdx)) {
            queue.add(nLinear);
          }
        }
      }
    }

    // Flood fill from four corners
    floodFill(0, 0);
    floodFill(width - 1, 0);
    floodFill(0, height - 1);
    floodFill(width - 1, height - 1);

    return result;
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
                setState(() => _overlayText = controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _aiStyleTransfer() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Style Transfer',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StyleChip(label: 'Cartoon', color: AppColors.coral),
                    _StyleChip(label: 'Anime', color: AppColors.purple),
                    _StyleChip(label: 'Pixel Art', color: AppColors.teal),
                    _StyleChip(label: 'Watercolor', color: Colors.blue),
                    _StyleChip(label: 'Pop Art', color: Colors.orange),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
    );
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

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final directory = await getApplicationDocumentsDirectory();
      final stickersDir = Directory('${directory.path}/stickers');
      if (!await stickersDir.exists()) {
        await stickersDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${stickersDir.path}/sticker_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      return filePath;
    } catch (e) {
      debugPrint('Failed to capture canvas: $e');
      return null;
    }
  }

  void _saveSticker() {
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sticker saved to $savedPath'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Sticker saved! Opening packs...',
                          ),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      context.push('/my-packs');
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Sticker Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            onPressed:
                _strokes.isNotEmpty
                    ? () => setState(() => _strokes.removeLast())
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded),
            onPressed: _saveSticker,
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
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                    overlayText: _overlayText,
                    textPosition: _textPosition,
                    hasRemovedBg: _hasRemovedbg,
                    selectedTool: selectedTool,
                    onStrokeStart: (offset) {
                      if (selectedTool == EditorTool.brush ||
                          selectedTool == EditorTool.eraser) {
                        setState(() => _currentStroke = [offset]);
                      }
                    },
                    onStrokeUpdate: (offset) {
                      if (selectedTool == EditorTool.brush ||
                          selectedTool == EditorTool.eraser) {
                        setState(() => _currentStroke.add(offset));
                      } else if (selectedTool == EditorTool.text ||
                          selectedTool == EditorTool.transform) {
                        setState(() => _textPosition = offset);
                      }
                    },
                    onStrokeEnd: () {
                      if (_currentStroke.isNotEmpty) {
                        setState(() {
                          _strokes.add(List.from(_currentStroke));
                          _currentStroke = [];
                        });
                      }
                    },
                  ),
                ),
              ),
              // Toolbar
              EditorToolbar(
                selectedTool: selectedTool,
                onToolSelected: (tool) {
                  HapticFeedback.selectionClick();
                  ref.read(selectedToolProvider.notifier).state = tool;
                },
                onRemoveBg: _removeBackground,
                onAddText: _addText,
                onAiStyle: _aiStyleTransfer,
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
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.coral),
                      SizedBox(height: 16),
                      Text('Removing background...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StyleChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: TextStyle(color: color)),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Applying $label style...')));
      },
    );
  }
}
