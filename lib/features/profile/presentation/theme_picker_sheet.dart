import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/sticker_themes.dart';
import '../../../core/theme/theme_provider.dart';

/// Opens the theme picker as a modal bottom sheet.
Future<void> showThemePickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(stickerThemeProvider);
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Text(
            'Choose Your Vibe',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick a theme that matches your style',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          // Theme grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: StickerThemes.all.length,
              itemBuilder: (context, index) {
                final theme = StickerThemes.all[index];
                final isSelected = theme.type == currentTheme.type;
                return _ThemePreviewCard(
                  theme: theme,
                  isSelected: isSelected,
                  onTap: () {
                    ref
                        .read(stickerThemeProvider.notifier)
                        .select(theme.type);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// =============================================================================
// Individual theme preview card
// =============================================================================

class _ThemePreviewCard extends StatelessWidget {
  final StickerThemeData theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.seedColor
                : Colors.grey.withValues(alpha: 0.15),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: theme.seedColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 17.5 : 19),
          child: Stack(
            children: [
              // Gradient banner at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: theme.gradient,
                  ),
                ),
              ),
              // Mini card previews
              Positioned(
                top: 28,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    // Mini card 1
                    Expanded(
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: theme.cardShadowColor.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.textSecondary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Mini card 2
                    Expanded(
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: theme.cardShadowColor.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.textSecondary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Background color sample strip
              Positioned(
                bottom: 34,
                left: 12,
                right: 12,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: theme.textSecondary.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
              // Theme name + accent dot
              Positioned(
                bottom: 8,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        theme.name,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Selection checkmark
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.seedColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.seedColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
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
