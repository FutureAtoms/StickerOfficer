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
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../core/widgets/text_style_sheet.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';

/// Maximum number of frames allowed (WhatsApp animated sticker limit).
const _kMaxFrames = StickerGuardrails.maxFrames;

/// Sticker canvas size in pixels.
const _kStickerSize = StickerGuardrails.stickerSize;

/// WhatsApp max file size for animated stickers in bytes (500 KB).
const _kMaxFileSize = StickerGuardrails.maxAnimatedSizeBytes;

class AnimatedStickerScreen extends ConsumerStatefulWidget {
  /// Optional list of file paths to pre-load as frames (e.g. from video extraction).
  final List<String>? initialFramePaths;

  /// Path to an FFmpeg-generated GIF (video-to-sticker flow). If set, this GIF
  /// is used directly on export when the user makes no edits.
  final String? ffmpegGifPath;

  /// Initial FPS from video conversion (video-to-sticker flow).
  final int? initialFps;

  const AnimatedStickerScreen({
    super.key,
    this.initialFramePaths,
    this.ffmpegGifPath,
    this.initialFps,
  });

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

  // -- Text overlay state ---------------------------------------------------
  String? _overlayText;
  StickerTextStyle _textStyle = const StickerTextStyle();
  TextAnimation _textAnimation = TextAnimation.none;

  // -- Video-sourced state ---------------------------------------------------
  String? _ffmpegGifPath;
  bool _isVideoSourced = false;
  bool _hasBeenEdited = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadInitialFrames();
  }

  /// Loads frames passed from the video-to-sticker screen (or any other source).
  Future<void> _loadInitialFrames() async {
    final paths = widget.initialFramePaths;
    if (paths == null || paths.isEmpty) return;

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _framePaths.add(path);
            _frameBytes.add(bytes);
          });
        }
      }
    }

    // Video-sourced sticker setup
    if (widget.ffmpegGifPath != null) {
      _ffmpegGifPath = widget.ffmpegGifPath;
      _isVideoSourced = true;

      if (widget.initialFps != null) {
        final fps = widget.initialFps!.clamp(
          StickerGuardrails.minFps,
          StickerGuardrails.videoMaxFps,
        );
        _frameDurationMs = (1000 / fps).round();
      }
    }

    _updateSizeEstimate();
  }

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
      _showSnackBar(
        'You already have $_kMaxFrames frames — that\'s the max!',
        AppColors.coral,
      );
      return;
    }

    final remaining = _kMaxFrames - _framePaths.length;

    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isEmpty) return;
      _hasBeenEdited = true;

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
          'Only added $remaining — $_kMaxFrames is the max!',
          AppColors.coral,
        );
      }

      _updateSizeEstimate();
    } catch (e) {
      _showSnackBar('Couldn\'t pick images — try again!', AppColors.coral);
    }
  }

  /// Import frames from an existing GIF file.
  Future<void> _importGif() async {
    if (_framePaths.length >= _kMaxFrames) {
      _showSnackBar(
        'You already have $_kMaxFrames frames — remove some first!',
        AppColors.coral,
      );
      return;
    }

    try {
      final xfile = await _picker.pickMedia();
      if (xfile == null) return;

      final bytes = await xfile.readAsBytes();
      final decoded = img.decodeGif(bytes);
      if (decoded == null) {
        _showSnackBar(
          'Couldn\'t read that file — pick a GIF!',
          AppColors.coral,
        );
        return;
      }

      final remaining = _kMaxFrames - _framePaths.length;
      final totalFrames = decoded.numFrames;
      final framesToTake = totalFrames.clamp(0, remaining);

      if (framesToTake == 0) {
        _showSnackBar('No room for more frames!', AppColors.coral);
        return;
      }

      // Save each frame as a PNG to a temp dir
      final tempDir = await getTemporaryDirectory();
      int added = 0;

      for (int i = 0; i < framesToTake; i++) {
        final frame = decoded.getFrame(i);
        final pngBytes = Uint8List.fromList(img.encodePng(frame));
        final path =
            '${tempDir.path}/gif_frame_${DateTime.now().millisecondsSinceEpoch}_$i.png';
        await File(path).writeAsBytes(pngBytes);

        setState(() {
          _framePaths.add(path);
          _frameBytes.add(pngBytes);
        });
        added++;
      }

      if (totalFrames > framesToTake) {
        _showSnackBar(
          'Added $added of $totalFrames frames (hit the $_kMaxFrames limit)',
          Colors.orange,
        );
      } else {
        _showSnackBar('Added $added frames from GIF!', AppColors.success);
      }

      _updateSizeEstimate();
    } catch (e) {
      _showSnackBar('GIF import failed — try a different file!', AppColors.coral);
    }
  }

  void _removeFrame(int index) {
    _hasBeenEdited = true;
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
    _hasBeenEdited = true;
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
    if (_framePaths.length < StickerGuardrails.minFrames) {
      _showSnackBar(
        'Add at least ${StickerGuardrails.minFrames} pictures to see it move!',
        AppColors.coral,
      );
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
    // Rough heuristic: sum of compressed frame sizes * 0.6
    final rawSum = _frameBytes.fold<int>(0, (s, b) => s + b.length);
    setState(() {
      _estimatedSize = (rawSum * 0.6).round();
    });
  }

  // ---------------------------------------------------------------------------
  // FPS helpers
  // ---------------------------------------------------------------------------

  int get _fps => (1000 / _frameDurationMs).round();

  /// Convert FPS to frame duration. Clamped between min and max FPS.
  void _setFps(double fps) {
    final maxFps = _isVideoSourced
        ? StickerGuardrails.videoMaxFps
        : StickerGuardrails.maxFps;
    final clamped = fps.clamp(
      StickerGuardrails.minFps.toDouble(),
      maxFps.toDouble(),
    );
    setState(() {
      _frameDurationMs = (1000 / clamped).round();
    });
    if (_isPlaying) {
      _stopAnimation();
      _startAnimation();
    }
  }

  // ---------------------------------------------------------------------------
  // Text overlay
  // ---------------------------------------------------------------------------

  void _showAddTextDialog() {
    final controller = TextEditingController(text: _overlayText ?? '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Text to Your Sticker!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: StickerGuardrails.maxTextLength,
                decoration: const InputDecoration(
                  hintText: 'Type something fun...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep it friendly and fun!',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (_overlayText != null)
              TextButton(
                onPressed: () {
                  setState(() => _overlayText = null);
                  Navigator.pop(ctx);
                },
                child: const Text('Remove'),
              ),
            FilledButton(
              onPressed: () {
                final text = StickerGuardrails.sanitizeText(controller.text);
                Navigator.pop(ctx);
                if (text.isNotEmpty) {
                  if (!StickerGuardrails.isKidSafeText(text)) {
                    _showSnackBar(
                      'Oops! Please use friendly words only.',
                      AppColors.coral,
                    );
                    return;
                  }
                  _showTextStyleSheet(text);
                }
              },
              child: const Text('Next'),
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
          showAnimationPicker: true,
          initialAnimation: _textAnimation,
          onApply: (style) {
            _hasBeenEdited = true;
            setState(() {
              _overlayText = text;
              _textStyle = style;
            });
          },
          onApplyWithAnimation: (style, anim) {
            _hasBeenEdited = true;
            setState(() {
              _overlayText = text;
              _textStyle = style;
              _textAnimation = anim;
            });
            _showSnackBar(
              'Text added! ${anim != TextAnimation.none ? "Animation: ${anim.label}" : ""}',
              AppColors.success,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _export() async {
    // Use video-specific or standard validation
    final errors = _isVideoSourced
        ? StickerGuardrails.validateVideoSticker(
            frameCount: _frameBytes.length,
            fps: _fps,
            sizeBytes: _estimatedSize,
            text: _overlayText,
          )
        : StickerGuardrails.validateAnimatedSticker(
            frameCount: _frameBytes.length,
            estimatedSizeBytes: _estimatedSize,
            fps: _fps,
            overlayText: _overlayText,
          );

    if (errors.isNotEmpty) {
      _showSnackBar(errors.first, AppColors.coral);
      return;
    }

    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();

    // Fast path: use FFmpeg GIF directly if no edits were made
    if (_isVideoSourced && !_hasBeenEdited && _ffmpegGifPath != null) {
      try {
        final gifFile = File(_ffmpegGifPath!);
        if (await gifFile.exists()) {
          final directory = await getApplicationDocumentsDirectory();
          final stickersDir = Directory('${directory.path}/stickers');
          if (!await stickersDir.exists()) {
            await stickersDir.create(recursive: true);
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filePath = '${stickersDir.path}/animated_$timestamp.gif';
          await gifFile.copy(filePath);

          if (!mounted) return;
          setState(() => _isExporting = false);
          await _showSaveToPackDialog(filePath);
          return;
        }
      } catch (_) {
        // Fall through to standard export
      }
    }

    try {
      // Compress frames to fit WhatsApp's 500KB animated sticker limit
      final compressedFrames = await StickerGuardrails.compressAnimatedFrames(
        _frameBytes,
      );

      // Decode all frames and build a GIF animation.
      final frames = <img.Image>[];
      for (final bytes in compressedFrames) {
        var decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        // Resize to 512x512
        decoded = img.copyResize(
          decoded,
          width: _kStickerSize,
          height: _kStickerSize,
          interpolation: img.Interpolation.linear,
        );

        // Burn text into each frame if overlay text is set,
        // applying the selected text animation transform per frame.
        if (_overlayText != null && _overlayText!.isNotEmpty) {
          const baseX = _kStickerSize ~/ 4;
          const baseY = _kStickerSize - 80;
          final transform = computeTextTransform(
            animation: _textAnimation,
            frameIndex: frames.length, // current frame index
            totalFrames: compressedFrames.length,
          );

          final drawX = (baseX + transform.dx).clamp(0, _kStickerSize - 1);
          final drawY = (baseY + transform.dy).clamp(0, _kStickerSize - 1);
          final drawAlpha = transform.alpha.clamp(0, 255);

          // Convert text color to RGBA components
          final r = _textStyle.color.r.toInt();
          final g = _textStyle.color.g.toInt();
          final b = _textStyle.color.b.toInt();

          img.drawString(
            decoded,
            _overlayText!,
            font: img.arial24,
            x: drawX,
            y: drawY,
            color: img.ColorRgba8(r, g, b, drawAlpha),
          );
        }

        // Set frame duration (in centiseconds for GIF)
        decoded.frameDuration = (_frameDurationMs / 10).round();
        frames.add(decoded);
      }

      if (frames.isEmpty) {
        _showSnackBar('Couldn\'t read your pictures — try different ones!', AppColors.coral);
        return;
      }

      // Build animation
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
          'Saved but it\'s ${StickerGuardrails.sizeLabel(actualSize)} — '
          'WhatsApp might not accept it!',
          Colors.orange,
        );
      }

      await _showSaveToPackDialog(filePath);
    } catch (e) {
      _showSnackBar('Something went wrong — try again!', AppColors.coral);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Save to pack dialog
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
                        hintText: 'Give your pack a cool name!',
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
                      items: existingPacks
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
      final packName = nameController.text.trim().isEmpty
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
      if (selectedExistingPack!.stickerPaths.length >=
          StickerGuardrails.maxStickersPerPack) {
        _showSnackBar(
          'This pack already has ${StickerGuardrails.maxStickersPerPack} stickers — that\'s the max!',
          AppColors.coral,
        );
        return;
      }
      final updatedPack = selectedExistingPack!.copyWith(
        stickerPaths: [...selectedExistingPack!.stickerPaths, stickerPath],
      );
      await ref.read(packsProvider.notifier).updatePack(updatedPack);
    } else {
      _showSnackBar('Pick a pack first!', AppColors.coral);
      return;
    }

    if (mounted) {
      _showAddAnotherDialog();
    }
  }

  /// After saving, offer to create another animated sticker for the same pack.
  void _showAddAnotherDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Sticker Saved!'),
          content: const Text(
            'Want to create another animated sticker?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) context.pop();
              },
              child: const Text('Done'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                // Reset for a new sticker
                _stopAnimation();
                setState(() {
                  _framePaths.clear();
                  _frameBytes.clear();
                  _currentFrame = 0;
                  _isPlaying = false;
                  _estimatedSize = 0;
                  _overlayText = null;
                  _textAnimation = TextAnimation.none;
                });
              },
              child: const Text('Create Another!'),
            ),
          ],
        );
      },
    );
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
        actions: [
          // Text overlay button
          IconButton(
            icon: Icon(
              _overlayText != null
                  ? Icons.text_fields_rounded
                  : Icons.text_fields_outlined,
              color: _overlayText != null ? AppColors.coral : null,
            ),
            tooltip: 'Add Text',
            onPressed: _showAddTextDialog,
          ),
        ],
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

                // -- Text overlay indicator -----------------------------------
                if (_overlayText != null) _buildTextOverlayBadge(theme),

                // -- Controls -------------------------------------------------
                _buildControls(theme),

                // -- Duration indicator ----------------------------------------
                if (_framePaths.length >= StickerGuardrails.minFrames)
                  _buildDurationIndicator(theme),

                // -- Import & Save buttons ------------------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // GIF import button
                      Expanded(
                        child: BubblyButton(
                          label: 'Import GIF',
                          icon: Icons.gif_box_rounded,
                          color: AppColors.teal,
                          onPressed: _importGif,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Save button
                      Expanded(
                        child: BubblyButton(
                          label: 'Save to Pack',
                          icon: Icons.save_rounded,
                          color: AppColors.purple,
                          isLoading: _isExporting,
                          onPressed: _export,
                        ),
                      ),
                    ],
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
                      Text('Creating your animated sticker...'),
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
              color: _framePaths.length >= _kMaxFrames
                  ? AppColors.coral.withValues(alpha:0.15)
                  : AppColors.purple.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_framePaths.length}/$_kMaxFrames',
              style: theme.textTheme.labelLarge?.copyWith(
                color: _framePaths.length >= _kMaxFrames
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
                if (oldIndex >= _framePaths.length ||
                    newIndex > _framePaths.length) {
                  return;
                }
                _onReorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
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
          color: canAdd
              ? AppColors.purple.withValues(alpha:0.12)
              : Colors.grey.withValues(alpha:0.1),
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
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.coral.withValues(alpha:0.3),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                  width: 22,
                  height: 22,
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
              color: AppColors.purple.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.purple.withValues(alpha:0.3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 64,
                  color: AppColors.purple.withValues(alpha:0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap to add pictures!',
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
                const SizedBox(height: 12),
                Text(
                  'or import a GIF below!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
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
                  color: AppColors.purple.withValues(alpha:0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.file(
                    File(_framePaths[_currentFrame]),
                    width: 260,
                    height: 260,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
                // Text overlay preview
                if (_overlayText != null && _overlayText!.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha:0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          if (_textStyle.hasOutline)
                            Text(
                              _overlayText!,
                              textAlign: TextAlign.center,
                              style: _textStyle.toOutlineTextStyle(
                                overrideSize: (_textStyle.size * 0.6).clamp(12.0, 28.0),
                              ),
                            ),
                          Text(
                            _overlayText!,
                            textAlign: TextAlign.center,
                            style: _textStyle.toTextStyle(
                              overrideSize: (_textStyle.size * 0.6).clamp(12.0, 28.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Play / pause
          IconButton(
            onPressed:
                _framePaths.length >= StickerGuardrails.minFrames
                    ? _togglePlay
                    : null,
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              size: 52,
              color: _framePaths.length >= StickerGuardrails.minFrames
                  ? AppColors.coral
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text overlay badge
  // ---------------------------------------------------------------------------

  Widget _buildTextOverlayBadge(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.purple.withValues(alpha:0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.text_fields, size: 18, color: AppColors.purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"$_overlayText"',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.purple,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_textAnimation != TextAnimation.none) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _textAnimation.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.coral,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _overlayText = null),
              child: const Icon(Icons.close, size: 18, color: AppColors.coral),
            ),
          ],
        ),
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
                    inactiveTrackColor: AppColors.purple.withValues(alpha:0.2),
                    thumbColor: AppColors.purple,
                    overlayColor: AppColors.purple.withValues(alpha:0.1),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: _fps.toDouble().clamp(
                      StickerGuardrails.minFps.toDouble(),
                      (_isVideoSourced
                              ? StickerGuardrails.videoMaxFps
                              : StickerGuardrails.maxFps)
                          .toDouble(),
                    ),
                    min: StickerGuardrails.minFps.toDouble(),
                    max: (_isVideoSourced
                            ? StickerGuardrails.videoMaxFps
                            : StickerGuardrails.maxFps)
                        .toDouble(),
                    divisions: (_isVideoSourced
                            ? StickerGuardrails.videoMaxFps
                            : StickerGuardrails.maxFps) -
                        StickerGuardrails.minFps,
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
    final status = StickerGuardrails.sizeStatus(
      _estimatedSize,
      isAnimated: true,
    );
    final sizeColor = StickerGuardrails.sizeColor(status);
    final fraction = (_estimatedSize / _kMaxFileSize).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.data_usage_rounded, color: sizeColor, size: 18),
            const SizedBox(width: 6),
            Text(
              'Size: ${StickerGuardrails.sizeLabel(_estimatedSize)} / 500 KB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: sizeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: sizeColor.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                StickerGuardrails.sizeTip(status, isAnimated: true),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: sizeColor,
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

  // ---------------------------------------------------------------------------
  // Duration indicator
  // ---------------------------------------------------------------------------

  Widget _buildDurationIndicator(ThemeData theme) {
    final durationMs = StickerGuardrails.totalDurationMs(
      _framePaths.length,
      _fps,
    );
    final durationLabel = StickerGuardrails.durationLabel(
      _framePaths.length,
      _fps,
    );
    final isSafe = StickerGuardrails.isDurationSafe(
      _framePaths.length,
      _fps,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: isSafe ? AppColors.textSecondary : AppColors.coral,
          ),
          const SizedBox(width: 6),
          Text(
            'Duration: $durationLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isSafe ? AppColors.textSecondary : AppColors.coral,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!isSafe) ...[
            const SizedBox(width: 8),
            Text(
              durationMs < StickerGuardrails.minDurationMs
                  ? 'Too short!'
                  : 'Too long!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.coral,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
