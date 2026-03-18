import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../editor_screen.dart';

class EditorToolbar extends StatelessWidget {
  final EditorTool selectedTool;
  final ValueChanged<EditorTool> onToolSelected;
  final VoidCallback onRemoveBg;
  final VoidCallback onAddText;
  final VoidCallback onAiStyle;
  final VoidCallback onAiCaption;

  const EditorToolbar({
    super.key,
    required this.selectedTool,
    required this.onToolSelected,
    required this.onRemoveBg,
    required this.onAddText,
    required this.onAiStyle,
    required this.onAiCaption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.auto_fix_high_rounded,
                label: 'AI BG',
                color: AppColors.purple,
                isSelected: false,
                onTap: onRemoveBg,
              ),
              _ToolButton(
                icon: Icons.gesture_rounded,
                label: 'Lasso',
                color: AppColors.coral,
                isSelected: selectedTool == EditorTool.lasso,
                onTap: () => onToolSelected(EditorTool.lasso),
              ),
              _ToolButton(
                icon: Icons.brush_rounded,
                label: 'Brush',
                color: AppColors.teal,
                isSelected: selectedTool == EditorTool.brush,
                onTap: () => onToolSelected(EditorTool.brush),
              ),
              _ToolButton(
                icon: Icons.auto_fix_normal_rounded,
                label: 'Eraser',
                color: Colors.orange,
                isSelected: selectedTool == EditorTool.eraser,
                onTap: () => onToolSelected(EditorTool.eraser),
              ),
              _ToolButton(
                icon: Icons.text_fields_rounded,
                label: 'Text',
                color: Colors.blue,
                isSelected: selectedTool == EditorTool.text,
                onTap: onAddText,
              ),
              _ToolButton(
                icon: Icons.palette_rounded,
                label: 'Style',
                color: AppColors.purple,
                isSelected: false,
                onTap: onAiStyle,
              ),
              _ToolButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Caption',
                color: AppColors.coral,
                isSelected: false,
                onTap: onAiCaption,
              ),
              _ToolButton(
                icon: Icons.open_with_rounded,
                label: 'Move',
                color: AppColors.textSecondary,
                isSelected: selectedTool == EditorTool.transform,
                onTap: () => onToolSelected(EditorTool.transform),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isSelected
                ? Border.all(color: color, width: 2)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
