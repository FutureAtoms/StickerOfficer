import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/sticker_themes.dart';
import '../theme/theme_provider.dart';

/// A card widget that adapts its appearance based on the current sticker theme.
///
/// - **Clay** theme: inset + outset shadow combo for a 3D pressed-clay look.
/// - **Frosted Glass** theme: semi-transparent background with [BackdropFilter].
/// - **All others**: standard elevated card with theme-appropriate shadow.
class ClayCard extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;

  const ClayCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(stickerThemeProvider);

    switch (theme.type) {
      case StickerThemeType.clay:
        return _buildClayCard(context, theme);
      case StickerThemeType.frostedGlass:
        return _buildGlassCard(context, theme);
      default:
        return _buildStandardCard(context, theme);
    }
  }

  // ---------------------------------------------------------------------------
  // Clay — raised soft surface with inset + outset shadows
  // ---------------------------------------------------------------------------
  Widget _buildClayCard(BuildContext context, StickerThemeData theme) {
    final bg = color ?? theme.cardColor;
    final radius = BorderRadius.circular(theme.cardRadius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: [
              // Outset light (top-left highlight)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                offset: const Offset(-4, -4),
                blurRadius: 12,
              ),
              // Outset dark (bottom-right shadow)
              BoxShadow(
                color: theme.cardShadowColor.withValues(alpha: 0.35),
                offset: const Offset(5, 5),
                blurRadius: 14,
              ),
              // Subtle inner glow (simulated via outer soft spread)
              BoxShadow(
                color: theme.seedColor.withValues(alpha: 0.06),
                offset: Offset.zero,
                blurRadius: 20,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Glass — BackdropFilter + semi-transparent surface
  // ---------------------------------------------------------------------------
  Widget _buildGlassCard(BuildContext context, StickerThemeData theme) {
    final radius = BorderRadius.circular(theme.cardRadius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (color ?? Colors.white).withValues(alpha: 0.75),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.cardShadowColor.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Standard — elevated card with rounded corners
  // ---------------------------------------------------------------------------
  Widget _buildStandardCard(BuildContext context, StickerThemeData theme) {
    final bg = color ?? theme.cardColor;
    final radius = BorderRadius.circular(theme.cardRadius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: theme.cardShadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
