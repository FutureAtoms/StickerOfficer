import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/image_picker_service.dart';
import '../../../core/utils/sticker_guardrails.dart';
import '../../../core/widgets/bubbly_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../domain/bulk_edit_queue.dart';
import 'editor_screen.dart';
import 'widgets/bulk_edit_progress.dart';

/// Orchestrator for bulk-editing multiple images into a sticker pack.
///
/// Pushed from Pack Detail. Picks multiple images, then walks the user
/// through each one: Edit (opens /editor in bulk mode), Skip (use original),
/// or Remove. Each accepted item is normalized and persisted immediately.
class BulkEditScreen extends ConsumerStatefulWidget {
  final String packId;

  const BulkEditScreen({super.key, required this.packId});

  @override
  ConsumerState<BulkEditScreen> createState() => _BulkEditScreenState();
}

class _BulkEditScreenState extends ConsumerState<BulkEditScreen> {
  BulkEditQueue? _queue;
  bool _isLoading = true;
  bool _isProcessing = false;
  StickerPack? _localPack;
  int _truncatedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImages());
  }

  Future<void> _pickImages() async {
    final pickerService = ref.read(imagePickerServiceProvider);
    final files = await pickerService.pickMultiImage();

    if (!mounted) return;

    if (files.isEmpty) {
      // User cancelled picker — go back
      Navigator.of(context).maybePop();
      return;
    }

    // Load current pack
    final repo = ref.read(packRepositoryProvider);
    final pack = repo.getPack(widget.packId);
    if (pack == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    _localPack = pack;

    // Enforce 30-sticker cap
    final available = StickerGuardrails.maxStickersPerPack - pack.stickerPaths.length;
    var paths = files.map((f) => f.path).toList();

    if (paths.length > available) {
      _truncatedCount = paths.length - available;
      paths = paths.sublist(0, available);
    }

    if (paths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This pack is already full (30 stickers)'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }

    setState(() {
      _queue = BulkEditQueue(paths);
      _isLoading = false;
    });

    // Show truncation warning
    if (_truncatedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $available images kept — pack can hold ${StickerGuardrails.maxStickersPerPack} stickers',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _handleEdit() async {
    final queue = _queue;
    if (queue == null || queue.isComplete) return;

    final item = queue.currentItem!;

    // Push editor in bulk mode, await the saved path
    final savedPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          child: EditorScreen(
            imagePath: item.originalPath,
            bulkMode: true,
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (savedPath == null) {
      // User cancelled — item stays pending, show queue again
      return;
    }

    // Normalize and persist
    await _processItem(BulkEditItemStatus.edited, tempPath: savedPath);
  }

  Future<void> _handleSkip() async {
    if (_queue == null || _queue!.isComplete) return;
    await _processItem(BulkEditItemStatus.skipped);
  }

  void _handleRemove() {
    if (_queue == null || _queue!.isComplete) return;
    setState(() {
      _queue!.markCurrentAndAdvance(BulkEditItemStatus.removed);
    });
  }

  Future<void> _processItem(BulkEditItemStatus status, {String? tempPath}) async {
    final queue = _queue!;
    final item = queue.currentItem!;

    setState(() => _isProcessing = true);

    try {
      // Read bytes from edited temp file or original
      final sourcePath = tempPath ?? item.originalPath;
      final sourceBytes = await File(sourcePath).readAsBytes();

      // Normalize to 512x512 PNG
      final normalized = StickerGuardrails.normalizeStaticSticker(sourceBytes);

      // Save to pack directory
      final packDir = await _ensurePackDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final stickerPath = '$packDir/sticker_$timestamp.png';
      await File(stickerPath).writeAsBytes(normalized);

      // Clean up temp file from editor
      if (tempPath != null) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }

      // Update local pack snapshot
      final newPaths = [..._localPack!.stickerPaths, stickerPath];
      _localPack = _localPack!.copyWith(
        stickerPaths: newPaths,
        trayIconPath: _localPack!.trayIconPath ?? stickerPath,
      );

      // Persist immediately
      final repo = ref.read(packRepositoryProvider);
      await repo.updatePack(_localPack!);

      // Advance queue
      setState(() {
        queue.markCurrentAndAdvance(status, savedPath: stickerPath);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process sticker: $e'),
            backgroundColor: AppColors.coral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
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
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Editing?'),
        content: Text(
          'You have $remaining images remaining. '
          '${saved > 0 ? '$saved stickers already saved to this pack will stay. ' : ''}'
          'Leave editing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue Editing'),
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
    // Refresh packs provider so Pack Detail picks up changes
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
          title: const Text('Add Stickers'),
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
            Text('Opening photo picker...'),
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
        if (_isProcessing)
          const LinearProgressIndicator(),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildCurrentItemView(BulkEditQueue queue) {
    final item = queue.currentItem!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            File(item.originalPath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: 200,
              height: 200,
              color: AppColors.pastels[0],
              child: const Icon(Icons.broken_image_rounded, size: 48),
            ),
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
            // Remove
            Expanded(
              child: BubblyButton(
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                color: AppColors.coral,
                onPressed: _isProcessing ? () {} : _handleRemove,
              ),
            ),
            const SizedBox(width: 12),
            // Skip
            Expanded(
              child: BubblyButton(
                label: 'Skip',
                icon: Icons.skip_next_rounded,
                color: AppColors.purple,
                onPressed: _isProcessing ? () {} : () => _handleSkip(),
              ),
            ),
            const SizedBox(width: 12),
            // Edit
            Expanded(
              child: BubblyButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                color: AppColors.teal,
                onPressed: _isProcessing ? () {} : () => _handleEdit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView(BulkEditQueue queue) {
    final edited = queue.countByStatus(BulkEditItemStatus.edited);
    final skipped = queue.countByStatus(BulkEditItemStatus.skipped);
    final removed = queue.countByStatus(BulkEditItemStatus.removed);
    final total = edited + skipped;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              total > 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 64,
              color: total > 0 ? AppColors.teal : AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              total > 0 ? '$total stickers added!' : 'No stickers added',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            if (edited > 0)
              Text('$edited edited', style: Theme.of(context).textTheme.bodyMedium),
            if (skipped > 0)
              Text('$skipped used as-is', style: Theme.of(context).textTheme.bodyMedium),
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
              color: AppColors.teal,
              onPressed: _finish,
            ),
          ],
        ),
      ),
    );
  }
}
