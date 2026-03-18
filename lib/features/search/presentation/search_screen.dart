import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

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
                      ? _PopularSection()
                      : _SearchResults(query: query),
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

class _PopularSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: 10,
      itemBuilder:
          (context, index) => GestureDetector(
            onTap: () => context.push('/pack/$index'),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.pastels[index % AppColors.pastels.length],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_emotions_rounded,
                      size: 40,
                      color: AppColors.coral.withOpacity(0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Popular Pack ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final String query;

  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
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
            'Searching for "$query"...',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
