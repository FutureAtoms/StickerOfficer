import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/models/sticker_pack.dart';
import '../../../data/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
    if (_searchController.text != value) {
      _searchController.text = value;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: value.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    // Keep controller in sync if provider changes externally
    if (_searchController.text != query) {
      _searchController.text = query;
    }

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
                  controller: _searchController,
                  onChanged:
                      (v) => ref.read(searchQueryProvider.notifier).state = v,
                  decoration: InputDecoration(
                    hintText: 'Search stickers, packs, creators...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => _setQuery(''),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
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

class _CategoryBubble extends ConsumerWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _CategoryBubble({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final isActive = query.toLowerCase() == label.toLowerCase();

    return Semantics(
      button: true,
      selected: isActive,
      label: '$label category',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GestureDetector(
          onTap: () {
            // Toggle: tap again to deselect
            final state = context.findAncestorStateOfType<_SearchScreenState>();
            if (isActive) {
              state?._setQuery('');
            } else {
              state?._setQuery(label);
            }
          },
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isActive ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: isActive
                      ? Border.all(color: color, width: 2.5)
                      : null,
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends ConsumerWidget {
  final String tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    // Strip # for comparison
    final tagValue = tag.startsWith('#') ? tag.substring(1) : tag;
    final isActive = query.toLowerCase() == tagValue.toLowerCase();

    return Semantics(
      button: true,
      selected: isActive,
      label: '$tag trending tag',
      child: GestureDetector(
        onTap: () {
          final state = context.findAncestorStateOfType<_SearchScreenState>();
          if (isActive) {
            state?._setQuery('');
          } else {
            // Strip # prefix so it matches actual tag data
            state?._setQuery(tagValue);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.coral.withValues(alpha: 0.2)
                : AppColors.pastels[tag.hashCode.abs() % AppColors.pastels.length],
            borderRadius: BorderRadius.circular(16),
            border: isActive
                ? Border.all(color: AppColors.coral, width: 2)
                : null,
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive ? AppColors.coral : AppColors.textPrimary,
            ),
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
      loading: () => const ShimmerSkeleton(itemCount: 4, layout: ShimmerLayout.grid),
      error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: AppColors.coral.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('Could not load packs'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(packsProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
      data: (packs) {
        if (packs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: AppColors.textSecondary.withValues(alpha:0.3),
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
      loading: () => const ShimmerSkeleton(itemCount: 4, layout: ShimmerLayout.grid),
      error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: AppColors.coral.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('Search failed'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(packsProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
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
                  color: AppColors.textSecondary.withValues(alpha:0.3),
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
    return Semantics(
      button: true,
      label: '${pack.name}, ${pack.stickerPaths.length} stickers',
      child: GestureDetector(
        onTap: () => context.push('/pack/${pack.id}'),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.pastels[index % AppColors.pastels.length],
            borderRadius: BorderRadius.circular(20),
          ),
        child: Stack(
          children: [
            // Thumbnail fills the card
            if (pack.stickerPaths.isNotEmpty)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(
                    File(pack.stickerPaths.first),
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, __, ___) => Center(
                          child: Icon(
                            Icons.emoji_emotions_rounded,
                            size: 48,
                            color: AppColors.coral.withValues(alpha: 0.3),
                          ),
                        ),
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.emoji_emotions_rounded,
                  size: 48,
                  color: AppColors.coral.withValues(alpha: 0.3),
                ),
              ),
            // Info overlay at bottom
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pack.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${pack.stickerPaths.length} stickers',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
