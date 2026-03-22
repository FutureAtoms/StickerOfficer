import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';

final feedTabProvider = StateProvider<int>((ref) => 0);

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(feedTabProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback:
                        (bounds) =>
                            AppColors.primaryGradient.createShader(bounds),
                    child: Text(
                      'StickerOfficer',
                      style: Theme.of(
                        context,
                      ).textTheme.displayLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_rounded),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            // Tab bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _TabPill(
                    label: 'Trending',
                    isActive: selectedTab == 0,
                    onTap: () => ref.read(feedTabProvider.notifier).state = 0,
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'For You',
                    isActive: selectedTab == 1,
                    onTap: () => ref.read(feedTabProvider.notifier).state = 1,
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'Challenges',
                    isActive: selectedTab == 2,
                    onTap: () => ref.read(feedTabProvider.notifier).state = 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Feed content
            Expanded(
              child:
                  selectedTab == 2
                      ? const _ChallengesTab()
                      : _StickerGrid(isTrending: selectedTab == 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label tab',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: isActive ? AppColors.primaryGradient : null,
            color: isActive ? null : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerGrid extends ConsumerWidget {
  final bool isTrending;

  const _StickerGrid({required this.isTrending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsProvider);

    return packsAsync.when(
      loading: () => const ShimmerSkeleton(itemCount: 6, layout: ShimmerLayout.grid),
      error:
          (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.coral.withValues(alpha:0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Something went wrong',
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
        if (packs.isEmpty) {
          return const _EmptyFeedState();
        }

        // Sort: trending = by likeCount desc, for you = by createdAt desc
        final sorted = List<StickerPack>.from(packs);
        if (isTrending) {
          sorted.sort((a, b) => b.likeCount.compareTo(a.likeCount));
        } else {
          sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }

        return RefreshIndicator(
          color: AppColors.coral,
          onRefresh: () async {
            ref.invalidate(packsProvider);
            await ref.read(packsProvider.future);
          },
          child: MasonryGridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final pack = sorted[index];
            final colorIndex = index % AppColors.pastels.length;
            final height = (index % 3 == 0) ? 220.0 : 180.0;

            return Semantics(
              button: true,
              label: '${pack.name}, ${pack.stickerPaths.length} stickers, ${pack.likeCount} likes',
              child: GestureDetector(
                onTap: () => context.push('/pack/${pack.id}'),
                child: Hero(
                  tag: 'pack-${pack.id}',
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.pastels[colorIndex],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadowLight,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Sticker thumbnail fills the tile
                        Positioned.fill(
                          child:
                              pack.stickerPaths.isNotEmpty
                                  ? ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.file(
                                      File(pack.stickerPaths.first),
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (_, __, ___) => Icon(
                                            Icons.emoji_emotions_rounded,
                                            size: 48,
                                            color: AppColors.coral.withValues(alpha:0.3),
                                          ),
                                    ),
                                  )
                                  : Center(
                                    child: Icon(
                                      Icons.emoji_emotions_rounded,
                                      size: 48,
                                      color: AppColors.coral.withValues(alpha:0.3),
                                    ),
                                  ),
                        ),
                        // Info overlay
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pack.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      '${pack.stickerPaths.length} stickers',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.favorite_rounded,
                                      size: 12,
                                      color: AppColors.coral,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${pack.likeCount}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .animate()
            .fadeIn(duration: 400.ms, delay: (index * 80).ms)
            .slideY(begin: 0.15, end: 0, duration: 400.ms, delay: (index * 80).ms, curve: Curves.easeOutCubic);
          },
          ),
        );
      },
    );
  }
}

class _EmptyFeedState extends StatelessWidget {
  const _EmptyFeedState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 72,
              color: AppColors.purple.withValues(alpha:0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'No stickers yet!',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first sticker pack and it will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => context.push('/editor'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.coral.withValues(alpha:0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Create Your First Sticker',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengesTab extends ConsumerWidget {
  const _ChallengesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenges = ref.watch(challengesProvider);

    if (challenges.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_events_rounded,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha:0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No challenges yet',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: challenges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final challenge = challenges[index];
        final color = challenge.isActive ? AppColors.coral : AppColors.purple;
        final daysLeft = challenge.endDate.difference(DateTime.now()).inDays;

        return _ChallengeCard(
          title: challenge.title,
          description: challenge.description,
          daysLeft: daysLeft.clamp(0, 999),
          submissions: challenge.submissionCount,
          color: color,
          isActive: challenge.isActive,
        );
      },
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final String title;
  final String description;
  final int daysLeft;
  final int submissions;
  final Color color;
  final bool isActive;

  const _ChallengeCard({
    required this.title,
    required this.description,
    required this.daysLeft,
    required this.submissions,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = isActive
        ? (daysLeft > 0 ? '$daysLeft days left' : 'Last day!')
        : 'Voting';

    return GestureDetector(
      onTap: () => context.push('/challenges'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha:0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha:0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.9),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '$submissions submissions',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.8),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Text(
                        isActive ? 'Join Now' : 'Vote',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
