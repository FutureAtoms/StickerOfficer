import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/report_button.dart';
import '../../../data/providers.dart';
import 'theme_picker_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);
    final authAsync = ref.watch(authStateProvider);
    final authUser = authAsync.valueOrNull;

    final stats = statsAsync.when(
      data: (s) => s,
      loading: () => const UserStats(
          packCount: 0, totalStickers: 0, totalLikes: 0, totalDownloads: 0),
      error: (_, __) => const UserStats(
          packCount: 0, totalStickers: 0, totalLikes: 0, totalDownloads: 0),
    );
    final publicId = authUser?.publicId;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Avatar
              Semantics(
                label: 'Profile avatar',
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: authUser?.photoUrl != null
                        ? null
                        : AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.coral.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: authUser?.photoUrl != null && authUser!.photoUrl!.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            authUser.photoUrl!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: Colors.white),
                          ),
                        )
                      : const Icon(Icons.person_rounded,
                          size: 48, color: Colors.white),
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 600.ms,
                      curve: Curves.easeOutBack),
              const SizedBox(height: 16),
              Text(
                  authUser?.displayName?.isNotEmpty == true
                      ? authUser!.displayName!
                      : 'Sticker Creator',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              if (publicId != null)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: publicId));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('ID copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  child: Text('@$publicId',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary)),
                )
              else
                Text('@stickermaker',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ProfileStat(value: '${stats.packCount}', label: 'Packs'),
                  _ProfileStat(
                    value: '${stats.totalStickers}',
                    label: 'Stickers',
                  ),
                  _ProfileStat(
                    value: _formatCount(stats.totalLikes),
                    label: 'Likes',
                  ),
                  _ProfileStat(
                    value: _formatCount(stats.totalDownloads),
                    label: 'Downloads',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Settings section
              _SettingsSection(
                items: [
                  // Sign In / Disconnect account
                  if (authUser == null || authUser.isAnonymous)
                    _SettingsItem(
                      icon: Icons.login_rounded,
                      label: 'Sign In',
                      color: AppColors.teal,
                      onTap: () => context.push('/login'),
                    )
                  else
                    _SettingsItem(
                      icon: Icons.link_off_rounded,
                      label: 'Disconnect ${authUser.method.name[0].toUpperCase()}${authUser.method.name.substring(1)}',
                      color: AppColors.coral,
                      onTap: () async {
                        final shouldDisconnect = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: const Text('Disconnect Account'),
                            content: const Text(
                              'This will disconnect your social account. '
                              'Your stickers and data will be kept.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text(
                                  'Disconnect',
                                  style: TextStyle(color: AppColors.coral),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (shouldDisconnect == true) {
                          ref.read(authStateProvider.notifier).disconnectProvider();
                        }
                      },
                    ),
                  _SettingsItem(
                    icon: Icons.palette_rounded,
                    label: 'Theme',
                    color: AppColors.purple,
                    onTap: () => showThemePickerSheet(context),
                  ),
                  _SettingsItem(
                    icon: Icons.privacy_tip_rounded,
                    label: 'Privacy Policy',
                    color: Colors.blue,
                    onTap: () => launchUrl(Uri.parse(
                        'https://sticker-officer-api.ceofutureatoms.workers.dev/legal/privacy')),
                  ),
                  _SettingsItem(
                    icon: Icons.description_rounded,
                    label: 'Terms of Service',
                    color: AppColors.purple,
                    onTap: () => launchUrl(Uri.parse(
                        'https://sticker-officer-api.ceofutureatoms.workers.dev/legal/terms')),
                  ),
                  _SettingsItem(
                    icon: Icons.help_rounded,
                    label: 'Contact Support',
                    color: Colors.orange,
                    onTap: () => launchUrl(
                        Uri.parse('mailto:support@futureatoms.com')),
                  ),
                  _SettingsItem(
                    icon: Icons.info_rounded,
                    label: 'About StickerOfficer',
                    color: AppColors.textSecondary,
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'StickerOfficer',
                        applicationVersion: '1.0.0',
                        applicationLegalese:
                            '© 2026 Future Atoms. All rights reserved.',
                      );
                    },
                  ),
                  _SettingsItem(
                    icon: Icons.flag_rounded,
                    label: 'Report an Issue',
                    color: AppColors.coral,
                    onTap: () => ReportButton.showReportSheet(
                      context: context,
                      ref: ref,
                      targetType: 'app',
                      targetId: publicId ?? 'unknown',
                    ),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 500.ms, delay: 300.ms)
              .slideY(begin: 0.15, end: 0, duration: 500.ms, delay: 300.ms),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final k = count / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    // Try to parse as number for animated counting
    final numericValue = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    final suffix = value.replaceAll(RegExp(r'[0-9]'), ''); // e.g. 'k'

    return Semantics(
      label: '$value $label',
      child: Column(
        children: [
          if (numericValue != null)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: numericValue),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, animatedValue, _) {
                return Text(
                  '$animatedValue$suffix',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                );
              },
            )
          else
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final List<_SettingsItem> items;

  const _SettingsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children:
            items.map((item) {
              final isLast = item == items.last;
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, color: item.color, size: 22),
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onTap: item.onTap,
                  ),
                  if (!isLast)
                    Divider(height: 1, indent: 72, color: Colors.grey.shade200),
                ],
              );
            }).toList(),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });
}
