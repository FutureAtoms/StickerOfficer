import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StickerCard extends StatelessWidget {
  final String? imageUrl;
  final String? label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final double borderRadius;

  const StickerCard({
    super.key,
    this.imageUrl,
    this.label,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: label ?? 'Sticker',
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border:
                isSelected
                    ? Border.all(color: AppColors.coral, width: 3)
                    : null,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowLight,
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child:
                      imageUrl != null
                          ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(),
                          )
                          : _placeholder(),
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      label!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.pastels[0],
      child: const Center(
        child: Icon(
          Icons.image_rounded,
          size: 32,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
