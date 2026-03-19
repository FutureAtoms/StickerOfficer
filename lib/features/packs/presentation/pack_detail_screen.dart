import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/whatsapp_button.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';
import '../../export/data/whatsapp_export_service.dart';

class PackDetailScreen extends ConsumerWidget {
  final String packId;

  const PackDetailScreen({super.key, required this.packId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsProvider);

    return packsAsync.when(
      loading:
          () => Scaffold(
            appBar: AppBar(title: const Text('Sticker Pack')),
            body: const Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, _) => Scaffold(
            appBar: AppBar(title: const Text('Sticker Pack')),
            body: Center(
              child: Text(
                'Failed to load pack',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
      data: (packs) {
        final pack = packs.where((p) => p.id == packId).firstOrNull;

        if (pack == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sticker Pack')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.textSecondary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pack not found',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return _PackDetailBody(pack: pack);
      },
    );
  }
}

class _PackDetailBody extends StatelessWidget {
  final StickerPack pack;

  const _PackDetailBody({required this.pack});

  @override
  Widget build(BuildContext context) {
    final stickerCount = pack.stickerPaths.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(pack.name),
        actions: [
          if (stickerCount < 30)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_rounded),
              tooltip: 'Add Sticker',
              onPressed: () => context.push('/editor'),
            ),
          IconButton(icon: const Icon(Icons.share_rounded), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pack header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child:
                              pack.trayIconPath != null
                                  ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.file(
                                      File(pack.trayIconPath!),
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) => const Icon(
                                            Icons.emoji_emotions_rounded,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                    ),
                                  )
                                  : const Icon(
                                    Icons.emoji_emotions_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pack.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'by ${pack.authorName}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatItem(
                        icon: Icons.favorite_rounded,
                        value: _formatCount(pack.likeCount),
                        label: 'Likes',
                        color: AppColors.coral,
                      ),
                      _StatItem(
                        icon: Icons.download_rounded,
                        value: _formatCount(pack.downloadCount),
                        label: 'Downloads',
                        color: AppColors.teal,
                      ),
                      _StatItem(
                        icon: Icons.photo_library_rounded,
                        value: '$stickerCount',
                        label: 'Stickers',
                        color: AppColors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Sticker grid
                  Row(
                    children: [
                      Text(
                        'Stickers ($stickerCount/30)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      if (stickerCount < 30)
                        TextButton.icon(
                          onPressed: () => context.push('/editor'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (stickerCount == 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.pastels[0].withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 48,
                            color: AppColors.textSecondary.withOpacity(0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No stickers in this pack yet',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: stickerCount,
                      itemBuilder: (context, index) {
                        final path = pack.stickerPaths[index];
                        return Container(
                          decoration: BoxDecoration(
                            color:
                                AppColors.pastels[index %
                                    AppColors.pastels.length],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => Center(
                                    child: Icon(
                                      Icons.emoji_emotions_rounded,
                                      color: AppColors.coral.withOpacity(0.3),
                                      size: 28,
                                    ),
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  // Tags
                  if (pack.tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          pack.tags
                              .map(
                                (tag) => Chip(
                                  label: Text('#$tag'),
                                  backgroundColor:
                                      AppColors.pastels[tag.hashCode.abs() %
                                          AppColors.pastels.length],
                                ),
                              )
                              .toList(),
                    ),
                ],
              ),
            ),
          ),
          // Fixed bottom bar with WhatsApp button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowLight,
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Like button
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.coral.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.favorite_border_rounded),
                      color: AppColors.coral,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Telegram button
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded),
                      color: Colors.blue,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  // WhatsApp button (PRIORITY #1)
                  Expanded(
                    child: WhatsAppButton(
                      onPressed: () => _exportToWhatsApp(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToWhatsApp(BuildContext context) async {
    // Show progress indicator.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Preparing stickers for sharing...'),
        backgroundColor: AppColors.whatsappGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    final exportService = WhatsAppExportService();

    // Build sticker data from real pack paths, falling back to placeholders
    // when there are no sticker files on disk.
    final stickerDataList = <StickerData>[];

    for (final path in pack.stickerPaths) {
      final file = File(path);
      if (await file.exists()) {
        stickerDataList.add(StickerData(data: await file.readAsBytes()));
      }
    }

    // If we have fewer than the minimum, pad with placeholder PNGs.
    while (stickerDataList.length < WhatsAppExportService.minStickersPerPack) {
      stickerDataList.add(StickerData(data: _placeholderPng()));
    }

    // Tray icon: use pack trayIconPath if available, otherwise first sticker.
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

  /// Generates a minimal 1x1 transparent PNG for placeholder stickers.
  static Uint8List _placeholderPng() {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final k = count / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
