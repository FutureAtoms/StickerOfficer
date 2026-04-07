import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/image_picker_service.dart';
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../domain/bulk_edit_queue.dart';
import 'video_to_sticker_screen.dart';
import 'widgets/bulk_edit_progress.dart';

/// Walks the user through multiple videos, one sticker conversion at a time.
class BulkVideoImportScreen extends ConsumerStatefulWidget {
  final String packId;

  const BulkVideoImportScreen({super.key, required this.packId});

  @override
  ConsumerState<BulkVideoImportScreen> createState() =>
      _BulkVideoImportScreenState();
}

class _BulkVideoImportScreenState extends ConsumerState<BulkVideoImportScreen> {
  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'avi',
    'webm',
    'mkv',
    '3gp',
  };

  BulkEditQueue? _queue;
  bool _isLoading = true;
  bool _isProcessing = false;
  StickerPack? _localPack;
  int _truncatedCount = 0;
  int _rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickVideos());
  }

  Future<void> _pickVideos() async {
    final repo = ref.read(packRepositoryProvider);
    final pack = repo.getPack(widget.packId);

    if (pack == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    if (!pack.type.isAnimated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'This pack only accepts animated video stickers.',
            ),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }

    _localPack = pack;

    final available =
        StickerGuardrails.maxStickersPerPack - pack.stickerPaths.length;
    if (available <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This pack is already full (30 stickers)'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }

    final pickerService = ref.read(imagePickerServiceProvider);
    final files = await pickerService.pickMultipleMedia(limit: available);

    if (!mounted) return;

    if (files.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }

    final videoFiles = files.where(_isVideoFile).toList(growable: false);
    _rejectedCount = files.length - videoFiles.length;

    var paths = videoFiles.map((file) => file.path).toList(growable: false);
    if (paths.length > available) {
      _truncatedCount = paths.length - available;
      paths = paths.take(available).toList(growable: false);
    }

    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No valid videos were selected.'),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _queue = BulkEditQueue(paths);
      _isLoading = false;
    });

    if (_rejectedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Skipped $_rejectedCount non-video item${_rejectedCount == 1 ? '' : 's'}.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else if (_truncatedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $available videos kept — pack can hold ${StickerGuardrails.maxStickersPerPack} stickers.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  bool _isVideoFile(XFile file) {
    if (file.mimeType?.startsWith('video/') == true) {
      return true;
    }

    final extension = file.path.split('.').last.toLowerCase();
    return _videoExtensions.contains(extension);
  }

  Future<void> _handleConvert() async {
    final queue = _queue;
    if (queue == null || queue.isComplete) return;

    final item = queue.currentItem!;
    final savedPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ProviderScope(
              child: VideoToStickerScreen(
                initialVideoPath: item.originalPath,
                bulkMode: true,
              ),
            ),
      ),
    );

    if (!mounted || savedPath == null) return;
    await _processConvertedVideo(savedPath);
  }

  void _handleRemove() {
    final queue = _queue;
    if (queue == null || queue.isComplete) return;

    setState(() {
      queue.markCurrentAndAdvance(BulkEditItemStatus.removed);
    });
  }

  Future<void> _processConvertedVideo(String sourcePath) async {
    final queue = _queue;
    if (queue == null || queue.isComplete || _localPack == null) return;

    setState(() => _isProcessing = true);

    try {
      final packDir = await _ensurePackDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = _normalizedExtension(sourcePath);
      final destinationPath = '$packDir/sticker_$timestamp.$extension';
      await File(sourcePath).copy(destinationPath);

      if (sourcePath != destinationPath) {
        try {
          await File(sourcePath).delete();
        } catch (_) {}
      }

      final newPaths = [..._localPack!.stickerPaths, destinationPath];
      _localPack = _localPack!.copyWith(
        stickerPaths: newPaths,
        trayIconPath: _localPack!.trayIconPath ?? destinationPath,
      );

      await ref.read(packRepositoryProvider).updatePack(_localPack!);

      setState(() {
        queue.markCurrentAndAdvance(
          BulkEditItemStatus.edited,
          savedPath: destinationPath,
        );
        _isProcessing = false;
      });
    } catch (error) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add animated sticker: $error'),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  String _normalizedExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    return extension.isEmpty ? 'gif' : extension;
  }

  Future<String> _ensurePackDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final packDir = '${dir.path}/stickers/${widget.packId}';
    await Directory(packDir).create(recursive: true);
    return packDir;
  }

  Future<bool> _onWillPop() async {
    final queue = _queue;
    if (queue == null || queue.isComplete) return true;

    final remaining = queue.remaining;
    final saved = queue.savedCount;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Leave Video Import?'),
            content: Text(
              'You have $remaining videos remaining. '
              '${saved > 0 ? '$saved animated stickers already saved to this pack will stay. ' : ''}'
              'Leave importing?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep Going'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    return shouldLeave ?? false;
  }

  void _finish() {
    ref.read(packsProvider.notifier).refresh();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          ref.read(packsProvider.notifier).refresh();
          navigator.maybePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Videos'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                ref.read(packsProvider.notifier).refresh();
                navigator.maybePop();
              }
            },
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening video picker...'),
          ],
        ),
      );
    }

    final queue = _queue!;

    if (queue.isComplete) {
      return _buildCompletionView(queue);
    }

    return Column(
      children: [
        BulkEditProgress(queue: queue),
        Expanded(child: _buildCurrentItemView(queue)),
        if (_isProcessing) const LinearProgressIndicator(),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildCurrentItemView(BulkEditQueue queue) {
    final item = queue.currentItem!;
    final name = item.originalPath.split('/').last;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.pastels[2].withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.video_library_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Open this clip in the video editor, convert it, and save the animated sticker back into this pack.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: BubblyButton(
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                color: AppColors.coral,
                onPressed: _isProcessing ? () {} : _handleRemove,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BubblyButton(
                label: 'Convert',
                icon: Icons.auto_awesome_motion_rounded,
                color: Colors.indigo,
                onPressed: _isProcessing ? () {} : _handleConvert,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView(BulkEditQueue queue) {
    final converted = queue.countByStatus(BulkEditItemStatus.edited);
    final removed = queue.countByStatus(BulkEditItemStatus.removed);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              converted > 0
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 64,
              color: converted > 0 ? Colors.indigo : AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              converted > 0
                  ? '$converted animated stickers added!'
                  : 'No videos converted',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (removed > 0)
              Text(
                '$removed removed',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 24),
            BubblyButton(
              label: 'Done',
              icon: Icons.check_rounded,
              color: Colors.indigo,
              onPressed: _finish,
            ),
          ],
        ),
      ),
    );
  }
}
