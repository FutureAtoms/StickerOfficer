import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../../../services/huggingface_provider.dart';

final aiPromptProvider = StateProvider<String>((ref) => '');
final aiGeneratingProvider = StateProvider<bool>((ref) => false);

class AiPromptScreen extends ConsumerStatefulWidget {
  const AiPromptScreen({super.key});

  @override
  ConsumerState<AiPromptScreen> createState() => _AiPromptScreenState();
}

class _AiPromptScreenState extends ConsumerState<AiPromptScreen> {
  final _controller = TextEditingController();
  bool _hasGenerated = false;
  bool _isSaving = false;

  final _suggestions = [
    'cute cat with sunglasses',
    'angry penguin holding coffee',
    'dancing pizza slice',
    'sleepy cloud with rainbow',
    'happy avocado with thumbs up',
    'surprised pikachu face',
  ];

  Future<void> _generate() async {
    if (_controller.text.trim().isEmpty) return;

    HapticFeedback.mediumImpact();
    ref.read(aiGeneratingProvider.notifier).state = true;
    ref.read(generatedStickersProvider.notifier).state = [];

    try {
      final apiService = ref.read(huggingFaceApiProvider);
      final images = await apiService.generateSticker(
        prompt: _controller.text.trim(),
        apiKey: kHuggingFaceApiKey,
      );

      if (!mounted) return;

      if (images.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No images were generated. Please try a different prompt.',
            ),
          ),
        );
      } else {
        ref.read(generatedStickersProvider.notifier).state = images;
        setState(() => _hasGenerated = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    } finally {
      if (mounted) {
        ref.read(aiGeneratingProvider.notifier).state = false;
      }
    }
  }

  /// Saves a single Uint8List to disk and returns the file path.
  Future<String> _saveStickerToDisk(Uint8List bytes) async {
    final appDir = await getApplicationDocumentsDirectory();
    final stickersDir = Directory('${appDir.path}/stickers');
    if (!await stickersDir.exists()) {
      await stickersDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${stickersDir.path}/ai_generated_$timestamp.png';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  /// Saves all generated stickers to disk and returns their file paths.
  Future<List<String>> _saveAllStickersToDisk() async {
    final stickers = ref.read(generatedStickersProvider);
    final paths = <String>[];
    for (final bytes in stickers) {
      final path = await _saveStickerToDisk(bytes);
      paths.add(path);
    }
    return paths;
  }

  /// Navigates to the editor after saving the sticker to disk.
  Future<void> _editInEditor(Uint8List bytes) async {
    setState(() => _isSaving = true);
    try {
      final filePath = await _saveStickerToDisk(bytes);
      if (!mounted) return;
      context.push('/editor', extra: filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save sticker: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Saves a single sticker to a new or existing pack.
  Future<void> _saveSingleToPack(Uint8List bytes) async {
    final packName = await _showPackNameDialog();
    if (packName == null || packName.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final filePath = await _saveStickerToDisk(bytes);
      const uuid = Uuid();
      final pack = StickerPack(
        id: uuid.v4(),
        name: packName.trim(),
        authorName: 'Me',
        stickerPaths: [filePath],
        trayIconPath: filePath,
        createdAt: DateTime.now(),
        tags: ['ai-generated'],
      );
      await ref.read(packsProvider.notifier).addPack(pack);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to pack "${pack.name}"')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Saves all generated stickers to a new pack.
  Future<void> _saveAllToPack() async {
    final stickers = ref.read(generatedStickersProvider);
    if (stickers.isEmpty) return;

    final packName = await _showPackNameDialog();
    if (packName == null || packName.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final paths = await _saveAllStickersToDisk();
      const uuid = Uuid();
      final pack = StickerPack(
        id: uuid.v4(),
        name: packName.trim(),
        authorName: 'Me',
        stickerPaths: paths,
        trayIconPath: paths.first,
        createdAt: DateTime.now(),
        tags: ['ai-generated'],
      );
      await ref.read(packsProvider.notifier).addPack(pack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${paths.length} stickers to pack "${pack.name}"',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Shows a dialog to enter a pack name.
  Future<String?> _showPackNameDialog() async {
    final nameController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Name your pack'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Funny Cats',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameController.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  /// Shows a bottom sheet with options for a tapped sticker.
  void _showStickerOptions(Uint8List bytes) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit in Editor'),
                  subtitle: const Text('Open in the sticker editor'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editInEditor(bytes);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save_rounded),
                  title: const Text('Save to Pack'),
                  subtitle: const Text('Create a new pack with this sticker'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveSingleToPack(bytes);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildResultsGrid(BuildContext context) {
    final stickers = ref.watch(generatedStickersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick your favorite:',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stickers.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _showStickerOptions(stickers[index]),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.pastels[index % AppColors.pastels.length],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.transparent, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Image.memory(
                    stickers[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 40,
                              color: AppColors.purple.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Failed to load',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Save All to Pack button
        SizedBox(
          width: double.infinity,
          child:
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : BubblyButton(
                    label: 'Save All to Pack',
                    icon: Icons.collections_rounded,
                    gradient: AppColors.primaryGradient,
                    onPressed: _saveAllToPack,
                  ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGenerating = ref.watch(aiGeneratingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Sticker Generator'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero
            ShaderMask(
              shaderCallback:
                  (bounds) => AppColors.primaryGradient.createShader(bounds),
              child: Text(
                'Describe your sticker',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI will create 4 variations for you to pick from!',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            // Input field
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. "cute cat wearing a top hat, waving hello"',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(20),
                ),
                onChanged: (v) => ref.read(aiPromptProvider.notifier).state = v,
              ),
            ),
            const SizedBox(height: 16),
            // Quick suggestions
            Text(
              'Try these:',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _suggestions.map((s) {
                    return GestureDetector(
                      onTap: () {
                        _controller.text = s;
                        ref.read(aiPromptProvider.notifier).state = s;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              AppColors.pastels[s.hashCode.abs() %
                                  AppColors.pastels.length],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            // Generate button
            BubblyButton(
              label: 'Generate Stickers',
              icon: Icons.auto_awesome_rounded,
              gradient: AppColors.primaryGradient,
              isLoading: isGenerating,
              onPressed: _generate,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '3 of 5 free generations remaining today',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            // Generated results
            if (_hasGenerated) _buildResultsGrid(context),
          ],
        ),
      ),
    );
  }
}
