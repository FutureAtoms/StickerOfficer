import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

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
                    shaderCallback: (bounds) =>
                        AppColors.primaryGradient.createShader(bounds),
                    child: Text(
                      'StickerOfficer',
                      style:
                          Theme.of(context).textTheme.displayLarge?.copyWith(
                                color: Colors.white,
                              ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
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
                    onTap: () =>
                        ref.read(feedTabProvider.notifier).state = 0,
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'For You',
                    isActive: selectedTab == 1,
                    onTap: () =>
                        ref.read(feedTabProvider.notifier).state = 1,
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'Challenges',
                    isActive: selectedTab == 2,
                    onTap: () =>
                        ref.read(feedTabProvider.notifier).state = 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Feed content
            Expanded(
              child: selectedTab == 2
                  ? _ChallengesTab()
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
    return GestureDetector(
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
    );
  }
}

class _StickerGrid extends StatelessWidget {
  final bool isTrending;

  const _StickerGrid({required this.isTrending});

  @override
  Widget build(BuildContext context) {
    // Sample data - in production, fetched from Firestore
    final items = List.generate(
      20,
      (i) => _PackPreview(
        name: isTrending
            ? 'Trending Pack ${i + 1}'
            : 'Recommended ${i + 1}',
        stickerCount: (i % 8) + 3,
        likes: isTrending ? (100 - i * 3) : (50 + i * 2),
        colorIndex: i % AppColors.pastels.length,
      ),
    );

    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final height = (index % 3 == 0) ? 220.0 : 180.0;

        return GestureDetector(
          onTap: () => context.push('/pack/${index}'),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.pastels[item.colorIndex],
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
                // Placeholder sticker grid
                Center(
                  child: Icon(
                    Icons.emoji_emotions_rounded,
                    size: 48,
                    color: AppColors.coral.withOpacity(0.3),
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
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
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
                              '${item.stickerCount} stickers',
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
                              '${item.likes}',
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
        );
      },
    );
  }
}

class _ChallengesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ChallengeCard(
          title: 'Funny Animals',
          description: 'Create the funniest animal stickers!',
          daysLeft: 3,
          submissions: 142,
          color: AppColors.coral,
          isActive: true,
        ),
        const SizedBox(height: 16),
        _ChallengeCard(
          title: 'Reaction Stickers',
          description: 'Express every emotion!',
          daysLeft: 0,
          submissions: 89,
          color: AppColors.purple,
          isActive: false,
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? '$daysLeft days left' : 'Voting',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.emoji_events_rounded,
                  color: Colors.white, size: 28),
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
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '$submissions submissions',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
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
            ],
          ),
        ],
      ),
    );
  }
}

class _PackPreview {
  final String name;
  final int stickerCount;
  final int likes;
  final int colorIndex;

  _PackPreview({
    required this.name,
    required this.stickerCount,
    required this.likes,
    required this.colorIndex,
  });
}
