import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/whatsapp_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../../export/data/whatsapp_export_service.dart';

class MyPacksScreen extends ConsumerWidget {
  const MyPacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'My Packs',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () => context.push('/editor'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // All packs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'All Packs',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            const Expanded(child: _PacksList()),
          ],
        ),
      ),
    );
  }
}

class _PacksList extends ConsumerWidget {
  const _PacksList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsProvider);

    return packsAsync.when(
      loading: () => const ShimmerSkeleton(itemCount: 4, layout: ShimmerLayout.list),
      error:
          (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.coral.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load packs',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(packsProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
      data: (packs) {
        return RefreshIndicator(
          color: AppColors.coral,
          onRefresh: () async {
            ref.invalidate(packsProvider);
            await ref.read(packsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (packs.isNotEmpty)
                ...packs.asMap().entries.map((entry) =>
                  _PackListItem(pack: entry.value)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: (entry.key * 100).ms)
                    .slideX(begin: -0.1, end: 0, duration: 400.ms, delay: (entry.key * 100).ms, curve: Curves.easeOutCubic),
                ),
              const SizedBox(height: 16),
              // Empty state CTA (always visible as a prompt to create more)
              _CreatePackCta(isEmpty: packs.isEmpty),
            ],
          ),
        );
      },
    );
  }
}

class _CreatePackCta extends StatelessWidget {
  final bool isEmpty;

  const _CreatePackCta({required this.isEmpty});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/editor'),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.pastels[4].withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.purple.withValues(alpha: 0.2),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 48,
              color: AppColors.purple.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isEmpty ? 'Create your first pack!' : 'Create a new pack!',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.purple),
            ),
            const SizedBox(height: 4),
            Text(
              'Add stickers and share on WhatsApp',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackListItem extends StatelessWidget {
  final StickerPack pack;

  const _PackListItem({required this.pack});

  Future<void> _exportToWhatsApp(BuildContext context) async {
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
        final raw = await file.readAsBytes();
        stickerDataList.add(StickerData(data: raw, sourcePath: path));
      }
    }

    // Pad to minimum 3 stickers with proper 512x512 placeholders
    while (stickerDataList.length < WhatsAppExportService.minStickersPerPack) {
      stickerDataList.add(StickerData(data: WhatsAppExportService.generatePlaceholderSticker()));
    }

    // Tray icon
    Uint8List trayIcon;
    if (pack.trayIconPath != null) {
      final trayFile = File(pack.trayIconPath!);
      if (await trayFile.exists()) {
        trayIcon = await trayFile.readAsBytes();
      } else {
        trayIcon = stickerDataList.first.data;
      }
    } else {
      trayIcon = stickerDataList.first.data;
    }

    final result = await exportService.exportToWhatsApp(
      packName: pack.name,
      packAuthor: pack.authorName,
      stickers: stickerDataList,
      trayIcon: trayIcon,
      trayIconSourcePath: pack.trayIconPath,
    );

    if (!context.mounted) return;

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

  @override
  Widget build(BuildContext context) {
    // Pick a color deterministically from the pack id
    final colorIndex = pack.id.hashCode.abs() % 3;
    final colors = [AppColors.coral, AppColors.teal, AppColors.purple];
    final color = colors[colorIndex];

    return Semantics(
      button: true,
      label: '${pack.name}, ${pack.stickerPaths.length} stickers. Tap to view, WhatsApp export available',
      child: GestureDetector(
        onTap: () => context.push('/pack/${pack.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      pack.stickerPaths.isNotEmpty
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(pack.stickerPaths.first),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => Icon(
                                    Icons.emoji_emotions_rounded,
                                    color: color,
                                    size: 28,
                                  ),
                            ),
                          )
                          : Icon(
                            Icons.emoji_emotions_rounded,
                            color: color,
                            size: 28,
                          ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${pack.stickerPaths.length} stickers',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => context.push('/pack/${pack.id}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // WhatsApp export button — actually calls export service
            WhatsAppButton(
              onPressed: () => _exportToWhatsApp(context),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
