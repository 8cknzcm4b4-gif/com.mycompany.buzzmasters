/// Daily rewards and rewarded adverts.
///
/// The advert is started by the player, and the coins are granted only after
/// the backend accepts the event — the prompt never adds a balance itself.
library;

import 'package:flutter/material.dart';

import '../../design/bm_theme.dart';
import '../../widgets/bm_button.dart';
import '../../widgets/bm_panel.dart';
import '../../widgets/studio_background.dart';
import '../bootstrap.dart';
import '../controller.dart';
import '../models.dart';
import '../rules.dart';

class DailyRewardsScreen extends StatelessWidget {
  const DailyRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final today = utcDayOf(DateTime.now());
        final usedToday = controller.adRewardsUsedToday;
        final cap = controller.policy.maxPerUtcDay;

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
                      'REWARDS CENTRE',
                      textAlign: TextAlign.center,
                      style: BmText.display(18, color: BmColors.pink),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              BmStatusBanner(controller: controller),
              BmPanel(
                color: BmColors.gold,
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on_rounded,
                        color: BmColors.gold, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('COIN BALANCE', style: BmText.label(10)),
                          Text('${controller.coins}',
                              style: BmText.display(22, color: Colors.white)),
                        ],
                      ),
                    ),
                    Text('DAY $today', style: BmText.label(9)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RewardTile(
                        title: 'Daily reward',
                        subtitle: 'One claim per UTC day.',
                        actionLabel: 'CLAIM',
                        color: BmColors.green,
                        enabled: !controller.busy,
                        onPressed: () => controller.claimDailyReward(),
                      ),
                      const SizedBox(height: 10),
                      _RewardTile(
                        title: 'Watch a rewarded advert',
                        subtitle:
                            '+${controller.policy.coinsPerReward} coins each — '
                            '$usedToday of $cap used today.',
                        actionLabel: 'WATCH',
                        color: BmColors.cyan,
                        enabled: usedToday < cap,
                        onPressed: () async {
                          await controller.openAdPrompt();
                          if (context.mounted) {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => const RewardedAdPrompt(),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('REWARD HISTORY', style: BmText.label(11)),
                      const SizedBox(height: 8),
                      if (controller.ledger.entries.isEmpty)
                        Text(
                          'No rewards yet.',
                          style: BmText.body(12, color: BmColors.muted),
                        )
                      else
                        for (final entry in controller.ledger.entries.reversed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(
                                  entry.reason == WalletReason.adReward
                                      ? Icons.ondemand_video_rounded
                                      : Icons.card_giftcard_rounded,
                                  size: 16,
                                  color: BmColors.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    switch (entry.reason) {
                                      WalletReason.adReward =>
                                        'Rewarded advert',
                                      WalletReason.dailyReward =>
                                        'Daily reward',
                                      WalletReason.purchaseGrant =>
                                        'Purchase bonus',
                                      WalletReason.adminAdjustment =>
                                        'Adjustment',
                                    },
                                    style: BmText.body(11),
                                  ),
                                ),
                                Text(
                                  '+${entry.delta}',
                                  style: BmText.title(12, color: BmColors.gold),
                                ),
                              ],
                            ),
                          ),
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

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.color,
    required this.onPressed,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final Color color;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return BmPanel(
      color: color,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BmText.title(14)),
                const SizedBox(height: 4),
                Text(subtitle, style: BmText.body(11, color: BmColors.muted)),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: BmButton(
              label: enabled ? actionLabel : 'LIMIT',
              height: 42,
              fontSize: 12,
              style: BmButtonStyle.cyan,
              onPressed: enabled ? onPressed : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while an advert loads and after it completes. It reports what the
/// server decided — it never grants coins itself.
class RewardedAdPrompt extends StatelessWidget {
  const RewardedAdPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final state = controller.adState;
        final title = switch (state) {
          AdPromptState.hidden => 'Rewarded advert',
          AdPromptState.loading => 'Loading…',
          AdPromptState.watching => 'Advertisement',
          AdPromptState.failed => 'No advert available',
        };
        final body = switch (state) {
          AdPromptState.hidden => 'Ready when you are.',
          AdPromptState.loading => 'Finding an advertisement.',
          AdPromptState.watching =>
            'Watch to the end to earn ${controller.policy.coinsPerReward} coins.',
          AdPromptState.failed => controller.ads.isConfigured
              ? 'No advertisement is available right now. Try again later.'
              : 'Advertising is not configured in this build.',
        };

        return AlertDialog(
          backgroundColor: BmColors.midnight,
          title: Text(title, style: BmText.title(15, color: BmColors.cyan)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body, style: BmText.body(12)),
              if (controller.message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(controller.message,
                    style: BmText.body(11, color: BmColors.gold)),
              ],
              const SizedBox(height: 6),
              Text(
                'Rewards are confirmed by the server.',
                style: BmText.label(9, color: BmColors.muted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (state == AdPromptState.watching)
              TextButton(
                onPressed: () async {
                  await controller.watchRewardedAd();
                },
                child: const Text('Play'),
              ),
          ],
        );
      },
    );
  }
}
