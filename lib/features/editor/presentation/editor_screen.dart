import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/editor_toolbar.dart';

enum EditorTool { none, lasso, brush, eraser, text, transform }

final selectedToolProvider = StateProvider<EditorTool>((ref) => EditorTool.none);
final brushSizeProvider = StateProvider<double>((ref) => 10.0);
final isProcessingProvider = StateProvider<bool>((ref) => false);

class EditorScreen extends ConsumerStatefulWidget {
  final String? imagePath;

  const EditorScreen({super.key, this.imagePath});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
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
    // In production, load from file path
    // For now, show placeholder
    setState(() {});
  }

  Future<void> _removeBackground() async {
    ref.read(isProcessingProvider.notifier).state = true;
    HapticFeedback.mediumImpact();

    // Simulate ONNX bg removal (~200ms in production)
    await Future.delayed(const Duration(seconds: 1));

    setState(() => _hasRemovedbg = true);
    ref.read(isProcessingProvider.notifier).state = false;

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
            decoration: const InputDecoration(
              hintText: 'Type your text...',
            ),
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
      builder: (ctx) => Padding(
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
      builder: (ctx) => Padding(
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

  void _saveSticker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
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
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sticker saved to pack!')),
                );
              },
            ),
            const SizedBox(height: 12),
            BubblyButton(
              label: 'Add to WhatsApp',
              icon: Icons.chat_rounded,
              color: AppColors.whatsappGreen,
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/my-packs');
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
            onPressed: _strokes.isNotEmpty
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applying $label style...')),
        );
      },
    );
  }
}
