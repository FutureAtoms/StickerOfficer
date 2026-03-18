import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Explore',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  onChanged:
                      (v) => ref.read(searchQueryProvider.notifier).state = v,
                  decoration: const InputDecoration(
                    hintText: 'Search stickers, packs, creators...',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Category bubbles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Categories',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: const [
                  _CategoryBubble(
                    label: 'Funny',
                    icon: Icons.mood_rounded,
                    color: AppColors.coral,
                  ),
                  _CategoryBubble(
                    label: 'Love',
                    icon: Icons.favorite_rounded,
                    color: Colors.pink,
                  ),
                  _CategoryBubble(
                    label: 'Animals',
                    icon: Icons.pets_rounded,
                    color: AppColors.teal,
                  ),
                  _CategoryBubble(
                    label: 'Memes',
                    icon: Icons.trending_up_rounded,
                    color: AppColors.purple,
                  ),
                  _CategoryBubble(
                    label: 'Anime',
                    icon: Icons.animation_rounded,
                    color: Colors.blue,
                  ),
                  _CategoryBubble(
                    label: 'Text',
                    icon: Icons.text_fields_rounded,
                    color: Colors.orange,
                  ),
                  _CategoryBubble(
                    label: 'Holidays',
                    icon: Icons.celebration_rounded,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Trending tags
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Trending Tags',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                      '#reaction',
                      '#cute',
                      '#funny',
                      '#mood',
                      '#anime',
                      '#kawaii',
                      '#meme',
                      '#love',
                      '#cat',
                      '#dog',
                    ].map((tag) => _TagChip(tag: tag)).toList(),
              ),
            ),
            const SizedBox(height: 20),
            // Results or popular packs
            Expanded(
              child:
                  query.isEmpty
                      ? const _PopularSection()
                      : const _SearchResults(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBubble extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _CategoryBubble({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: () {},
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              AppColors.pastels[tag.hashCode.abs() % AppColors.pastels.length],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          tag,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PopularSection extends ConsumerWidget {
  const _PopularSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsProvider);

    return packsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load packs')),
      data: (packs) {
        if (packs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: AppColors.textSecondary.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No packs yet. Create one to get started!',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Sort by likes descending for "popular"
        final sorted = List<StickerPack>.from(packs)
          ..sort((a, b) => b.likeCount.compareTo(a.likeCount));

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final pack = sorted[index];
            return _PackGridItem(pack: pack, index: index);
          },
        );
      },
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Search failed')),
      data: (results) {
        if (results.isEmpty) {
          final query = ref.watch(searchQueryProvider);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 64,
                  color: AppColors.textSecondary.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No results for "$query"',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final pack = results[index];
            return _PackGridItem(pack: pack, index: index);
          },
        );
      },
    );
  }
}

class _PackGridItem extends StatelessWidget {
  final StickerPack pack;
  final int index;

  const _PackGridItem({required this.pack, required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/pack/${pack.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pastels[index % AppColors.pastels.length],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pack.stickerPaths.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(pack.stickerPaths.first),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => Icon(
                          Icons.emoji_emotions_rounded,
                          size: 40,
                          color: AppColors.coral.withOpacity(0.4),
                        ),
                  ),
                )
              else
                Icon(
                  Icons.emoji_emotions_rounded,
                  size: 40,
                  color: AppColors.coral.withOpacity(0.4),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  pack.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${pack.stickerPaths.length} stickers',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
