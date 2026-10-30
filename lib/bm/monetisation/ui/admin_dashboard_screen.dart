/// Administrator-only monetisation dashboard.
///
/// Every figure comes from the backend's admin summary. A figure with no
/// connected source renders "Not connected" — this screen never invents a
/// number, and the database function refuses callers who are not
/// administrators.
library;

import 'package:flutter/material.dart';

import '../../design/bm_theme.dart';
import '../../widgets/bm_panel.dart';
import '../../widgets/studio_background.dart';
import '../bootstrap.dart';
import '../models.dart';

class AdminMonetisationDashboardScreen extends StatelessWidget {
  const AdminMonetisationDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final summary = controller.revenue;
        final notConnected = !controller.backend.isConfigured;

        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'MONETISATION ADMIN',
                      textAlign: TextAlign.center,
                      style: BmText.display(17, color: BmColors.cyan),
                    ),
                  ),
                  IconButton(
                    onPressed: controller.loadAdmin,
                    icon:
                        const Icon(Icons.refresh_rounded, color: BmColors.cyan),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Administrator access only',
                textAlign: TextAlign.center,
                style: BmText.body(11, color: BmColors.muted),
              ),
              const SizedBox(height: 12),
              if (notConnected)
                BmPanel(
                  color: BmColors.red,
                  child: Text(
                    'Backend not connected — no revenue source is available. '
                    'Figures below are shown as "Not connected" rather than £0.',
                    style: BmText.body(12),
                  ),
                )
              else
                BmStatusBanner(controller: controller),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COUNTS', style: BmText.label(11)),
                      const SizedBox(height: 8),
                      _CountGrid(summary: summary),
                      const SizedBox(height: 16),
                      Text('REVENUE BY CHANNEL', style: BmText.label(11)),
                      const SizedBox(height: 8),
                      _MoneyRow(
                          label: 'VIP subscriptions (MRR)',
                          value: summary.vipMrr),
                      _MoneyRow(
                          label: 'Cosmetic purchases',
                          value: summary.cosmeticGross),
                      _MoneyRow(
                          label: 'Advertising earnings',
                          value: summary.adEarnings),
                      _MoneyRow(
                          label: 'Sponsored campaigns',
                          value: summary.sponsorRevenue),
                      const SizedBox(height: 16),
                      Text('GROSS TO NET', style: BmText.label(11)),
                      const SizedBox(height: 8),
                      _MoneyRow(label: 'Gross revenue', value: summary.gross),
                      _MoneyRow(
                          label: 'Store fees',
                          value: summary.fees,
                          negative: true),
                      _MoneyRow(
                          label: 'Refunds',
                          value: summary.refunds,
                          negative: true),
                      _MoneyRow(
                          label: 'Tax estimate',
                          value: summary.taxEstimate,
                          negative: true),
                      const Divider(color: BmColors.panelEdge, height: 22),
                      _MoneyRow(label: 'Net revenue', value: summary.net),
                      const SizedBox(height: 16),
                      BmPanel(
                        color: BmColors.red,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('OUTSTANDING ERRORS',
                                style: BmText.label(10, color: BmColors.red)),
                            const SizedBox(height: 6),
                            Text(
                              '${summary.outstandingErrors} monetisation error(s) awaiting attention.',
                              style: BmText.body(12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Gross, fees, refunds and tax are reported separately and '
                        'are never combined unless every source is connected. '
                        'No earnings source has been configured for this build, '
                        'so no advertising or store revenue is displayed.',
                        style: BmText.body(10, color: BmColors.muted),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CountGrid extends StatelessWidget {
  const _CountGrid({required this.summary});

  final AdminRevenueSummary summary;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      ('ACTIVE VIP', '${summary.activeVipCount}'),
      ('CANCELLATIONS 30D', '${summary.cancellations30d}'),
      ('VERIFIED AD REWARDS', '${summary.verifiedAdRewards}'),
      (
        'REFUNDS',
        summary.refunds.connected ? summary.refunds.formatted : 'Not connected'
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final (label, value) in cells)
          BmPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: BmText.label(9)),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.display(17, color: BmColors.gold),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.negative = false,
  });

  final String label;
  final MoneyStream value;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: BmText.body(12)),
          ),
          Text(
            value.connected && negative
                ? '−${value.formatted}'
                : value.formatted,
            style: BmText.title(13,
                color: value.connected
                    ? (negative ? BmColors.red : BmColors.gold)
                    : BmColors.muted),
          ),
        ],
      ),
    );
  }
}
