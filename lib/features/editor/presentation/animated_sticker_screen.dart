import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';

/// Maximum number of frames allowed (WhatsApp animated sticker limit).
const _kMaxFrames = 8;

/// Sticker canvas size in pixels.
const _kStickerSize = 512;

/// WhatsApp max file size for animated stickers in bytes (500 KB).
const _kMaxFileSize = 500 * 1024;

class AnimatedStickerScreen extends ConsumerStatefulWidget {
  const AnimatedStickerScreen({super.key});

  @override
  ConsumerState<AnimatedStickerScreen> createState() =>
      _AnimatedStickerScreenState();
}

class _AnimatedStickerScreenState extends ConsumerState<AnimatedStickerScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  /// Paths to the frame images the user has imported.
  final List<String> _framePaths = [];

  /// Decoded image objects (for preview).
  final List<Uint8List> _frameBytes = [];

  /// Current frame index shown in the preview.
  int _currentFrame = 0;

  /// Whether the animation preview is playing.
  bool _isPlaying = false;

  /// Timer that drives the preview animation.
  Timer? _animTimer;

  /// Frame duration in milliseconds. Default 125ms = 8 fps.
  int _frameDurationMs = 125;

  /// Estimated output file size in bytes.
  int _estimatedSize = 0;

  /// Whether an export is currently in progress.
  bool _isExporting = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _stopAnimation();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Frame management
  // ---------------------------------------------------------------------------

  Future<void> _addFrames() async {
    if (_framePaths.length >= _kMaxFrames) {
      _showSnackBar('Maximum $_kMaxFrames frames reached!', AppColors.coral);
      return;
    }

    final remaining = _kMaxFrames - _framePaths.length;

    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: _kStickerSize.toDouble(),
        maxHeight: _kStickerSize.toDouble(),
      );

      if (images.isEmpty) return;

      final toAdd = images.take(remaining).toList();

      for (final xfile in toAdd) {
        final bytes = await xfile.readAsBytes();
        setState(() {
          _framePaths.add(xfile.path);
          _frameBytes.add(bytes);
        });
      }

      if (images.length > remaining) {
        _showSnackBar(
          'Only $remaining more frame(s) allowed — extras were skipped.',
          AppColors.coral,
        );
      }

      _updateSizeEstimate();
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', AppColors.coral);
    }
  }

  void _removeFrame(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _framePaths.removeAt(index);
      _frameBytes.removeAt(index);
      if (_currentFrame >= _framePaths.length) {
        _currentFrame = _framePaths.isEmpty ? 0 : _framePaths.length - 1;
      }
    });
    _updateSizeEstimate();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final path = _framePaths.removeAt(oldIndex);
      final bytes = _frameBytes.removeAt(oldIndex);
      _framePaths.insert(newIndex, path);
      _frameBytes.insert(newIndex, bytes);
    });
  }

  // ---------------------------------------------------------------------------
  // Animation preview
  // ---------------------------------------------------------------------------

  void _togglePlay() {
    if (_framePaths.length < 2) {
      _showSnackBar('Add at least 2 frames to preview!', AppColors.coral);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startAnimation();
    } else {
      _stopAnimation();
    }
  }

  void _startAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(Duration(milliseconds: _frameDurationMs), (_) {
      if (!mounted) return;
      setState(() {
        _currentFrame = (_currentFrame + 1) % _framePaths.length;
      });
    });
  }

  void _stopAnimation() {
    _animTimer?.cancel();
    _animTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Size estimation
  // ---------------------------------------------------------------------------

  void _updateSizeEstimate() {
    if (_frameBytes.isEmpty) {
      setState(() => _estimatedSize = 0);
      return;
    }
    // Rough heuristic: sum of compressed frame sizes * 0.6 (GIF overhead is
    // typically less than raw JPEG but includes palette and framing).
    final rawSum = _frameBytes.fold<int>(0, (s, b) => s + b.length);
    setState(() {
      _estimatedSize = (rawSum * 0.6).round();
    });
  }

  Color _sizeColor() {
    if (_estimatedSize < 300 * 1024) return AppColors.success;
    if (_estimatedSize < 450 * 1024) return Colors.orange;
    return AppColors.coral;
  }

  String _sizeLabel() {
    final kb = _estimatedSize / 1024;
    if (kb < 1) return '0 KB';
    return '${kb.toStringAsFixed(0)} KB';
  }

  // ---------------------------------------------------------------------------
  // FPS helpers
  // ---------------------------------------------------------------------------

  int get _fps => (1000 / _frameDurationMs).round();

  /// Convert FPS to frame duration. Clamped between 4 and 8 fps.
  void _setFps(double fps) {
    final clamped = fps.clamp(4.0, 8.0);
    setState(() {
      _frameDurationMs = (1000 / clamped).round();
    });
    // Restart timer if playing
    if (_isPlaying) {
      _stopAnimation();
      _startAnimation();
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _export() async {
    if (_frameBytes.length < 2) {
      _showSnackBar('Add at least 2 frames to export!', AppColors.coral);
      return;
    }

    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();

    try {
      // Decode all frames and build a GIF animation.
      final frames = <img.Image>[];
      for (final bytes in _frameBytes) {
        var decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        // Resize to 512x512
        decoded = img.copyResize(
          decoded,
          width: _kStickerSize,
          height: _kStickerSize,
          interpolation: img.Interpolation.linear,
        );
        // Set frame duration (in centiseconds for GIF)
        decoded.frameDuration = (_frameDurationMs / 10).round();
        frames.add(decoded);
      }

      if (frames.isEmpty) {
        _showSnackBar('Could not decode frames.', AppColors.coral);
        return;
      }

      // Build animation: first frame is the base, rest are addFrame'd.
      final animation = frames.first.clone();
      for (var i = 1; i < frames.length; i++) {
        animation.addFrame(frames[i]);
      }

      final gifBytes = img.encodeGif(animation);

      // Save to documents directory
      final directory = await getApplicationDocumentsDirectory();
      final stickersDir = Directory('${directory.path}/stickers');
      if (!await stickersDir.exists()) {
        await stickersDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${stickersDir.path}/animated_$timestamp.gif';
      final file = File(filePath);
      await file.writeAsBytes(gifBytes);

      if (!mounted) return;

      final actualSize = gifBytes.length;
      if (actualSize > _kMaxFileSize) {
        _showSnackBar(
          'Exported (${(actualSize / 1024).toStringAsFixed(0)} KB) — '
          'may exceed WhatsApp 500 KB limit!',
          Colors.orange,
        );
      }

      await _showSaveToPackDialog(filePath);
    } catch (e) {
      _showSnackBar('Export failed: $e', AppColors.coral);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Save to pack dialog (mirrors EditorScreen pattern)
  // ---------------------------------------------------------------------------

  Future<void> _showSaveToPackDialog(String stickerPath) async {
    final packsAsync = ref.read(packsProvider);
    final existingPacks = packsAsync.valueOrNull ?? [];
    final nameController = TextEditingController(text: 'My Animated Stickers');
    StickerPack? selectedExistingPack;
    bool createNew = existingPacks.isEmpty;

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
              ? 'My Animated Stickers'
              : nameController.text.trim();
      final newPack = StickerPack(
        id: const Uuid().v4(),
        name: packName,
        authorName: 'Me',
        stickerPaths: [stickerPath],
        createdAt: DateTime.now(),
      );
      await ref.read(packsProvider.notifier).addPack(newPack);
    } else if (selectedExistingPack != null) {
      final updatedPack = selectedExistingPack!.copyWith(
        stickerPaths: [...selectedExistingPack!.stickerPaths, stickerPath],
      );
      await ref.read(packsProvider.notifier).updatePack(updatedPack);
    } else {
      _showSnackBar('No pack selected', AppColors.coral);
      return;
    }

    if (mounted) {
      _showSnackBar('Animated sticker saved to pack!', AppColors.success);
    }
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
        title: const Text('Animated Sticker'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // -- Frame strip -----------------------------------------------
                _buildFrameStrip(theme),
                const SizedBox(height: 8),

                // -- Preview area ---------------------------------------------
                Expanded(child: _buildPreview(theme)),

                // -- Controls -------------------------------------------------
                _buildControls(theme),

                // -- Save button ----------------------------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: BubblyButton(
                    label: 'Save to Pack',
                    icon: Icons.save_rounded,
                    color: AppColors.purple,
                    isLoading: _isExporting,
                    onPressed: _export,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // Export overlay
          if (_isExporting)
            Container(
              color: Colors.black38,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.purple),
                      SizedBox(height: 16),
                      Text('Creating animated sticker...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Frame strip
  // ---------------------------------------------------------------------------

  Widget _buildFrameStrip(ThemeData theme) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Frame count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:
                  _framePaths.length >= _kMaxFrames
                      ? AppColors.coral.withOpacity(0.15)
                      : AppColors.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_framePaths.length}/$_kMaxFrames',
              style: theme.textTheme.labelLarge?.copyWith(
                color:
                    _framePaths.length >= _kMaxFrames
                        ? AppColors.coral
                        : AppColors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Scrollable frame thumbnails
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _framePaths.length + 1,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                // Ignore the add-button position
                if (oldIndex >= _framePaths.length ||
                    newIndex > _framePaths.length) {
                  return;
                }
                _onReorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                // Last item is the "add" button
                if (index == _framePaths.length) {
                  return _buildAddButton(key: const ValueKey('add-btn'));
                }
                return _buildFrameThumb(index, key: ValueKey('frame-$index'));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton({required Key key}) {
    final canAdd = _framePaths.length < _kMaxFrames;
    return GestureDetector(
      key: key,
      onTap: canAdd ? _addFrames : null,
      child: Container(
        width: 70,
        height: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color:
              canAdd
                  ? AppColors.purple.withOpacity(0.12)
                  : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canAdd ? AppColors.purple : Colors.grey.shade300,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Icon(
          Icons.add_photo_alternate_rounded,
          size: 28,
          color: canAdd ? AppColors.purple : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildFrameThumb(int index, {required Key key}) {
    final isSelected = index == _currentFrame;
    return GestureDetector(
      key: key,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentFrame = index);
      },
      child: Container(
        width: 70,
        height: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.coral : Colors.transparent,
            width: 3,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: AppColors.coral.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ]
                  : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(
                File(_framePaths[index]),
                width: 70,
                height: 70,
                fit: BoxFit.cover,
              ),
            ),
            // Frame number badge
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Delete button
            Positioned(
              right: 2,
              top: 2,
              child: GestureDetector(
                onTap: () => _removeFrame(index),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  Widget _buildPreview(ThemeData theme) {
    if (_framePaths.isEmpty) {
      return Center(
        child: GestureDetector(
          onTap: _addFrames,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              color: AppColors.purple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.purple.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 64,
                  color: AppColors.purple.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap to add frames!',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Up to $_kMaxFrames images',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The preview image
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purple.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                File(_framePaths[_currentFrame]),
                width: 260,
                height: 260,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Play / pause
          IconButton(
            onPressed: _framePaths.length >= 2 ? _togglePlay : null,
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              size: 52,
              color:
                  _framePaths.length >= 2
                      ? AppColors.coral
                      : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Controls (speed + size)
  // ---------------------------------------------------------------------------

  Widget _buildControls(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Speed slider
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(
                'Speed',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$_fps FPS',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Slow',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.purple,
                    inactiveTrackColor: AppColors.purple.withOpacity(0.2),
                    thumbColor: AppColors.purple,
                    overlayColor: AppColors.purple.withOpacity(0.1),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: _fps.toDouble(),
                    min: 4,
                    max: 8,
                    divisions: 4,
                    onChanged: (v) => _setFps(v),
                  ),
                ),
              ),
              Text(
                'Fast',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Size indicator
          if (_framePaths.isNotEmpty) _buildSizeBar(theme),
        ],
      ),
    );
  }

  Widget _buildSizeBar(ThemeData theme) {
    final sizeColor = _sizeColor();
    final fraction = (_estimatedSize / _kMaxFileSize).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.data_usage_rounded, color: sizeColor, size: 18),
            const SizedBox(width: 6),
            Text(
              'Size: ${_sizeLabel()} / 500 KB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: sizeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_estimatedSize > 450 * 1024)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.coral.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Too large!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.coral,
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
            color: sizeColor,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
