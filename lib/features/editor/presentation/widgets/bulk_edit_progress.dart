import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/bulk_edit_queue.dart';

/// Displays progress through the bulk edit queue.
///
/// Shows "Editing N of M" label, a progress bar, and thumbnail strip
/// with status indicators for each item.
class BulkEditProgress extends StatelessWidget {
  final BulkEditQueue queue;

  const BulkEditProgress({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    final current = queue.currentIndex + 1;
    final total = queue.total;
    final progress = total > 0 ? current / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                queue.isComplete ? 'All done!' : 'Editing $current of $total',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${queue.savedCount} saved',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.pastels[0].withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.teal),
            ),
          ),
          const SizedBox(height: 10),
          // Thumbnail strip
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = queue.items[index];
                return _ThumbnailChip(
                  item: item,
                  isCurrent: index == queue.currentIndex && !queue.isComplete,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailChip extends StatelessWidget {
  final BulkEditItem item;
  final bool isCurrent;

  const _ThumbnailChip({required this.item, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? AppColors.coral : Colors.transparent,
          width: isCurrent ? 2.5 : 0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(item.originalPath),
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) => Container(
                    color: AppColors.pastels[0],
                    child: const Icon(Icons.image, size: 20),
                  ),
            ),
            // Status overlay
            if (item.status != BulkEditItemStatus.pending)
              Container(
                color: _overlayColor(item.status),
                child: Center(child: _statusIcon(item.status)),
              ),
          ],
        ),
      ),
    );
  }

  Color _overlayColor(BulkEditItemStatus status) {
    switch (status) {
      case BulkEditItemStatus.edited:
        return Colors.green.withValues(alpha: 0.5);
      case BulkEditItemStatus.skipped:
        return Colors.blue.withValues(alpha: 0.5);
      case BulkEditItemStatus.removed:
        return Colors.red.withValues(alpha: 0.5);
      case BulkEditItemStatus.pending:
        return Colors.transparent;
    }
  }

  Widget _statusIcon(BulkEditItemStatus status) {
    switch (status) {
      case BulkEditItemStatus.edited:
        return const Icon(Icons.check_rounded, color: Colors.white, size: 20);
      case BulkEditItemStatus.skipped:
        return const Icon(
          Icons.skip_next_rounded,
          color: Colors.white,
          size: 20,
        );
      case BulkEditItemStatus.removed:
        return const Icon(Icons.close_rounded, color: Colors.white, size: 20);
      case BulkEditItemStatus.pending:
        return const SizedBox.shrink();
    }
  }
}
