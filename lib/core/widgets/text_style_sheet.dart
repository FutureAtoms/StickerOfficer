import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../utils/sticker_guardrails.dart';

/// All configurable properties for sticker overlay text.
class StickerTextStyle {
  final Color color;
  final double size;
  final bool bold;
  final bool italic;
  final String fontFamily;
  final bool hasOutline;
  final Color outlineColor;

  const StickerTextStyle({
    this.color = Colors.white,
    this.size = 28.0,
    this.bold = true,
    this.italic = false,
    this.fontFamily = 'Nunito',
    this.hasOutline = false,
    this.outlineColor = Colors.black,
  });

  StickerTextStyle copyWith({
    Color? color,
    double? size,
    bool? bold,
    bool? italic,
    String? fontFamily,
    bool? hasOutline,
    Color? outlineColor,
  }) {
    return StickerTextStyle(
      color: color ?? this.color,
      size: size ?? this.size,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      fontFamily: fontFamily ?? this.fontFamily,
      hasOutline: hasOutline ?? this.hasOutline,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }

  /// Build a Flutter [TextStyle] from this config.
  TextStyle toTextStyle({double? overrideSize}) {
    final fontSize = overrideSize ?? size;
    final fontWeight = bold ? FontWeight.w700 : FontWeight.w400;
    final fontStyle = italic ? FontStyle.italic : FontStyle.normal;

    TextStyle base;
    switch (fontFamily) {
      case 'Lobster':
        base = GoogleFonts.lobster(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      case 'Bangers':
        base = GoogleFonts.bangers(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      case 'Pacifico':
        base = GoogleFonts.pacifico(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      case 'Permanent Marker':
        base = GoogleFonts.permanentMarker(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      case 'Press Start 2P':
        base = GoogleFonts.pressStart2p(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      case 'Luckiest Guy':
        base = GoogleFonts.luckiestGuy(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
      default: // Nunito
        base = GoogleFonts.nunito(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
        );
    }

    return base.copyWith(
      shadows: const [
        Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 1)),
      ],
    );
  }

  /// Build a stroke/outline [TextStyle] for painting behind the fill text.
  TextStyle toOutlineTextStyle({double? overrideSize}) {
    final base = toTextStyle(overrideSize: overrideSize);
    return base.copyWith(
      foreground:
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..color = outlineColor,
      color: null,
      shadows: [],
    );
  }
}

/// Available font options for sticker text.
const kFontOptions = <MapEntry<String, String>>[
  MapEntry('Nunito', 'Aa'),
  MapEntry('Lobster', 'Aa'),
  MapEntry('Bangers', 'Aa'),
  MapEntry('Pacifico', 'Aa'),
  MapEntry('Permanent Marker', 'Aa'),
  MapEntry('Press Start 2P', 'Ab'),
  MapEntry('Luckiest Guy', 'Aa'),
];

/// Expanded color palette for sticker text.
const kTextColorOptions = <MapEntry<String, Color>>[
  MapEntry('White', Colors.white),
  MapEntry('Black', Colors.black),
  MapEntry('Red', Color(0xFFE53935)),
  MapEntry('Pink', Color(0xFFEC407A)),
  MapEntry('Purple', Color(0xFFAB47BC)),
  MapEntry('Deep Purple', Color(0xFF7E57C2)),
  MapEntry('Blue', Color(0xFF42A5F5)),
  MapEntry('Cyan', Color(0xFF26C6DA)),
  MapEntry('Teal', Color(0xFF26A69A)),
  MapEntry('Green', Color(0xFF66BB6A)),
  MapEntry('Lime', Color(0xFFD4E157)),
  MapEntry('Yellow', Color(0xFFFFEE58)),
  MapEntry('Orange', Color(0xFFFFA726)),
  MapEntry('Deep Orange', Color(0xFFFF7043)),
  MapEntry('Brown', Color(0xFF8D6E63)),
  MapEntry('Coral', Color(0xFFFF6B6B)),
];

/// A bottom sheet for styling sticker overlay text.
///
/// Shows a live preview and controls for font, color, size, bold, italic,
/// and outline. Calls [onApply] with the final [StickerTextStyle].
///
/// If [showAnimationPicker] is true, also shows a [TextAnimation] picker
/// and calls [onApplyWithAnimation].
class TextStyleBottomSheet extends StatefulWidget {
  final String text;
  final StickerTextStyle initialStyle;
  final ValueChanged<StickerTextStyle> onApply;

  /// For animated stickers: also pick a text animation.
  final bool showAnimationPicker;
  final TextAnimation? initialAnimation;
  final void Function(StickerTextStyle style, TextAnimation animation)?
  onApplyWithAnimation;

  const TextStyleBottomSheet({
    super.key,
    required this.text,
    required this.initialStyle,
    required this.onApply,
    this.showAnimationPicker = false,
    this.initialAnimation,
    this.onApplyWithAnimation,
  });

  @override
  State<TextStyleBottomSheet> createState() => _TextStyleBottomSheetState();
}

class _TextStyleBottomSheetState extends State<TextStyleBottomSheet> {
  late StickerTextStyle _style;
  late TextAnimation _animation;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
    _animation = widget.initialAnimation ?? TextAnimation.none;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Style Your Text!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(height: 8),

            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Stack(
                  children: [
                    if (_style.hasOutline)
                      Text(
                        widget.text,
                        style: _style.toOutlineTextStyle(
                          overrideSize: _style.size.clamp(16, 40),
                        ),
                      ),
                    Text(
                      widget.text,
                      style: _style.toTextStyle(
                        overrideSize: _style.size.clamp(16, 40),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Font picker
            _buildSectionLabel('Font'),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kFontOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = kFontOptions[index];
                  final isSelected = _style.fontFamily == entry.key;
                  return _buildFontChip(entry.key, isSelected);
                },
              ),
            ),
            const SizedBox(height: 16),

            // Color picker
            _buildSectionLabel('Pick a Color'),
            const SizedBox(height: 8),
            _buildColorGrid(),
            const SizedBox(height: 16),

            // Size slider
            Row(
              children: [
                _buildSectionLabel('Size'),
                const SizedBox(width: 8),
                Text(
                  '${_style.size.round()}px',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            Slider(
              value: _style.size,
              min: StickerGuardrails.minTextSize,
              max: StickerGuardrails.maxTextSize,
              divisions: 48,
              activeColor: AppColors.coral,
              label: '${_style.size.round()}px',
              onChanged: (val) {
                setState(() => _style = _style.copyWith(size: val));
              },
            ),

            // Style toggles row: Bold, Italic, Outline
            _buildSectionLabel('Bold'),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildToggleChip(
                  label: 'B',
                  isActive: _style.bold,
                  fontWeight: FontWeight.w900,
                  onTap:
                      () => setState(
                        () => _style = _style.copyWith(bold: !_style.bold),
                      ),
                ),
                const SizedBox(width: 10),
                _buildToggleChip(
                  label: 'I',
                  isActive: _style.italic,
                  fontStyle: FontStyle.italic,
                  onTap:
                      () => setState(
                        () => _style = _style.copyWith(italic: !_style.italic),
                      ),
                ),
                const SizedBox(width: 10),
                _buildToggleChip(
                  label: 'O',
                  isActive: _style.hasOutline,
                  isOutline: true,
                  onTap:
                      () => setState(
                        () =>
                            _style = _style.copyWith(
                              hasOutline: !_style.hasOutline,
                            ),
                      ),
                ),
                if (_style.hasOutline) ...[
                  const SizedBox(width: 12),
                  // Outline color mini picker
                  _buildOutlineColorPicker(),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Animation picker (animated stickers only)
            if (widget.showAnimationPicker) ...[
              _buildSectionLabel('Animation'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    TextAnimation.values.map((anim) {
                      final isSelected = _animation == anim;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _animation = anim);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient:
                                isSelected ? AppColors.primaryGradient : null,
                            color: isSelected ? null : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? AppColors.coral
                                      : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                anim.icon,
                                size: 16,
                                color:
                                    isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                anim.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isSelected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Apply button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (widget.showAnimationPicker) {
                    widget.onApplyWithAnimation?.call(_style, _animation);
                  } else {
                    widget.onApply(_style);
                  }
                  Navigator.pop(context);
                },
                child: const Text(
                  'Add to Sticker!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }

  Widget _buildFontChip(String fontFamily, bool isSelected) {
    // Build a small preview of the font
    TextStyle previewStyle;
    switch (fontFamily) {
      case 'Lobster':
        previewStyle = GoogleFonts.lobster(
          fontSize: 16,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      case 'Bangers':
        previewStyle = GoogleFonts.bangers(
          fontSize: 16,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      case 'Pacifico':
        previewStyle = GoogleFonts.pacifico(
          fontSize: 14,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      case 'Permanent Marker':
        previewStyle = GoogleFonts.permanentMarker(
          fontSize: 13,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      case 'Press Start 2P':
        previewStyle = GoogleFonts.pressStart2p(
          fontSize: 9,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      case 'Luckiest Guy':
        previewStyle = GoogleFonts.luckiestGuy(
          fontSize: 15,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
      default:
        previewStyle = GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _style = _style.copyWith(fontFamily: fontFamily));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.coral : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Aa', style: previewStyle.copyWith(height: 0.9)),
            const SizedBox(height: 1),
            Text(
              fontFamily == 'Permanent Marker'
                  ? 'Marker'
                  : (fontFamily == 'Press Start 2P'
                      ? 'Pixel'
                      : (fontFamily == 'Luckiest Guy' ? 'Lucky' : fontFamily)),
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white70 : AppColors.textSecondary,
                height: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          kTextColorOptions.map((entry) {
            final isSelected =
                _style.color.toARGB32() == entry.value.toARGB32();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _style = _style.copyWith(color: entry.value));
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.coral : Colors.grey.shade400,
                    width: isSelected ? 3 : 1.5,
                  ),
                  boxShadow:
                      isSelected
                          ? [
                            BoxShadow(
                              color: AppColors.coral.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                          : null,
                ),
                child:
                    isSelected
                        ? Icon(
                          Icons.check,
                          size: 18,
                          color:
                              entry.value.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                        )
                        : null,
              ),
            );
          }).toList(),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    bool isOutline = false,
  }) {
    final displayLabel = label == 'B' ? 'B  ${isActive ? 'ON' : 'OFF'}' : label;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: label == 'B' ? 92 : 48,
        height: 48,
        decoration: BoxDecoration(
          color:
              isActive
                  ? AppColors.purple.withValues(alpha: 0.15)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? AppColors.purple : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Center(
          child:
              isOutline
                  ? Stack(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          foreground:
                              Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 2
                                ..color =
                                    isActive
                                        ? AppColors.purple
                                        : AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color:
                              isActive
                                  ? AppColors.purple.withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                        ),
                      ),
                    ],
                  )
                  : Text(
                    displayLabel,
                    style: TextStyle(
                      fontSize: label == 'B' ? 16 : 20,
                      fontWeight: fontWeight ?? FontWeight.w700,
                      fontStyle: fontStyle ?? FontStyle.normal,
                      color:
                          isActive ? AppColors.purple : AppColors.textSecondary,
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildOutlineColorPicker() {
    const outlineColors = [
      Colors.black,
      Colors.white,
      Color(0xFFE53935),
      Color(0xFF42A5F5),
      Color(0xFF66BB6A),
      Color(0xFFFFEE58),
    ];

    return Row(
      children:
          outlineColors.map((color) {
            final isSelected =
                _style.outlineColor.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () {
                setState(() => _style = _style.copyWith(outlineColor: color));
              },
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.coral : Colors.grey.shade400,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}
