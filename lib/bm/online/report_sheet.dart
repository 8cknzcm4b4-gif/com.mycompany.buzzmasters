import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import 'online_race_service.dart';

/// Asks for a report reason; null when the player cancels.
Future<T?> pickReportReason<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> reasons,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: BmColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: BmText.display(16, color: BmColors.gold)),
            const SizedBox(height: 4),
            Text('Reports are reviewed by the Buzz Masters team.',
                style: BmText.body(12, color: BmColors.muted)),
            const SizedBox(height: 8),
            for (final (value, label) in reasons)
              ListTile(
                key: ValueKey('report-reason-$label'),
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: BmText.body(14)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: BmColors.muted),
                onTap: () => Navigator.of(sheet).pop(value),
              ),
            TextButton(
              onPressed: () => Navigator.of(sheet).pop(),
              child: Text('CANCEL', style: BmText.label(11)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reports a question the player was shown in an online race.
Future<void> reportOnlineQuestion(
    BuildContext context, String roomId, int questionIndex) async {
  final reason = await pickReportReason<QuestionReportReason>(
    context,
    title: 'REPORT THIS QUESTION',
    reasons: [for (final r in QuestionReportReason.values) (r, r.label)],
  );
  if (reason == null || !context.mounted) return;
  final result =
      await OnlineRace.service.reportQuestion(roomId, questionIndex, reason);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: BmColors.panel,
    content: Text(
        result.ok ? 'Thanks — the question was reported.' : result.message,
        style: BmText.body(12.5)),
  ));
}
