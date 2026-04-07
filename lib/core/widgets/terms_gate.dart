import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';

class TermsGate {
  static const _acceptedKey = 'terms_accepted';

  static Future<bool> hasAccepted(SharedPreferences prefs) async {
    return prefs.getBool(_acceptedKey) ?? false;
  }

  static Future<bool> showIfNeeded(
    BuildContext context,
    SharedPreferences prefs, {
    VoidCallback? onAccepted,
  }) async {
    if (prefs.getBool(_acceptedKey) == true) return true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _TermsDialog(),
    );

    if (accepted == true) {
      await prefs.setBool(_acceptedKey, true);
      onAccepted?.call();
      return true;
    }
    return false;
  }
}

class _TermsDialog extends StatelessWidget {
  const _TermsDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Terms of Service'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'By publishing sticker packs, you agree to:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            _BulletPoint('You own or have rights to all content you publish'),
            _BulletPoint(
              'Your content does not violate copyright or trademarks',
            ),
            _BulletPoint(
              'Your content is not harmful, hateful, or inappropriate',
            ),
            _BulletPoint(
              'StickerOfficer may remove content that violates these terms',
            ),
            _BulletPoint('Other users may report content for review'),
            SizedBox(height: 12),
            Text(
              'Full terms and privacy policy are available in the app settings.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Decline'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.coral,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text('I Accept'),
        ),
      ],
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u2022 ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
