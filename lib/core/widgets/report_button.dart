import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../../data/providers.dart';

class ReportButton extends StatelessWidget {
  final String targetType;
  final String targetId;
  final WidgetRef ref;

  const ReportButton({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.ref,
  });

  static void showReportSheet({
    required BuildContext context,
    required WidgetRef ref,
    required String targetType,
    required String targetId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReportSheet(
        targetType: targetType,
        targetId: targetId,
        ref: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined, size: 22),
      tooltip: 'Report',
      onPressed: () => showReportSheet(
        context: context,
        ref: ref,
        targetType: targetType,
        targetId: targetId,
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final WidgetRef ref;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.ref,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _selectedReason;
  final _detailsController = TextEditingController();

  static const _reasons = [
    'inappropriate',
    'copyright',
    'spam',
    'harassment',
    'other',
  ];

  static const _reasonLabels = {
    'inappropriate': 'Inappropriate Content',
    'copyright': 'Copyright Violation',
    'spam': 'Spam',
    'harassment': 'Harassment',
    'other': 'Other',
  };

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Report ${widget.targetType}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          ..._reasons.map((reason) => RadioListTile<String>(
                value: reason,
                groupValue: _selectedReason,
                title: Text(_reasonLabels[reason] ?? reason),
                activeColor: AppColors.coral,
                onChanged: (val) => setState(() => _selectedReason = val),
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Additional details (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedReason == null
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      try {
                        await widget.ref.read(apiClientProvider).report(
                              targetType: widget.targetType,
                              targetId: widget.targetId,
                              reason: _selectedReason!,
                              details: _detailsController.text.trim().isEmpty
                                  ? null
                                  : _detailsController.text.trim(),
                            );
                      } catch (_) {}
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report submitted')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Submit Report'),
            ),
          ),
        ],
      ),
    );
  }
}
