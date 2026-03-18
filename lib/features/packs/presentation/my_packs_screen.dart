import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/whatsapp_button.dart';

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
            // Recently exported
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Recently Exported',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.whatsappGreen,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 3,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 80,
                    decoration: BoxDecoration(
                      color: AppColors.pastels[index],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.whatsappGreen.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.whatsappGreen,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pack ${index + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // All packs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'All Packs',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _PacksList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PacksList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Empty state for new users
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Sample packs
        ...List.generate(3, (i) => _PackListItem(index: i)),
        const SizedBox(height: 16),
        // Empty state CTA
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.pastels[4].withOpacity(0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.purple.withOpacity(0.2),
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 48,
                color: AppColors.purple.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Create a new pack!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.purple,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add stickers and share on WhatsApp',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PackListItem extends StatelessWidget {
  final int index;

  const _PackListItem({required this.index});

  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.coral, AppColors.teal, AppColors.purple];
    final names = ['My Favorites', 'Reactions', 'Custom Memes'];
    final counts = [8, 12, 5];

    return Container(
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
                  color: colors[index].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.emoji_emotions_rounded,
                  color: colors[index],
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names[index],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${counts[index]} stickers',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: AppColors.textSecondary),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          // WhatsApp export button
          WhatsAppButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Preparing stickers for WhatsApp...'),
                  backgroundColor: AppColors.whatsappGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
