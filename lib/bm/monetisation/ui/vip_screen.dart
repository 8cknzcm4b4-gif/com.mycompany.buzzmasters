/// VIP membership: paywall, benefits, plan selector, membership management and
/// purchase history.
///
/// Prices are read from the store; the brief's figures (£3.99 / £29.99) are
/// only what the store is expected to be configured with, never something the
/// app hardcodes.
library;

import 'package:flutter/material.dart';

import '../../design/bm_theme.dart';
import '../../widgets/bm_button.dart';
import '../../widgets/bm_panel.dart';
import '../../widgets/studio_background.dart';
import '../bootstrap.dart';
import '../controller.dart';
import '../models.dart';

class _VipHeader extends StatelessWidget {
  const _VipHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: BmText.display(18, color: BmColors.gold),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

/// The paywall: benefits, plan selector, purchase, restore and status.
class VipMembershipScreen extends StatefulWidget {
  const VipMembershipScreen({super.key});

  @override
  State<VipMembershipScreen> createState() => _VipMembershipScreenState();
}

class _VipMembershipScreenState extends State<VipMembershipScreen> {
  VipPeriod _selected = VipPeriod.monthly;

  Future<void> _buy(MonetisationController controller) async {
    final productId = _selected == VipPeriod.monthly
        ? ProductIds.vipMonthly
        : ProductIds.vipAnnual;
    final product = controller.productFor(productId);
    if (product == null || !product.hasPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This plan is not available from your store yet.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.midnight,
        title: Text('Start VIP?',
            style: BmText.title(15, color: BmColors.gold)),
        content: Text(
          '${product.title} — ${product.priceString}\n\n'
          'Billed by your app store. Cancel any time.',
          style: BmText.body(12, color: BmColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.buyVip(productId);
  }

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final monthly = controller.productFor(ProductIds.vipMonthly);
        final annual = controller.productFor(ProductIds.vipAnnual);
        final active = controller.vipActive;

        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              const _VipHeader(title: 'BUZZ MASTERS VIP'),
              const SizedBox(height: 4),
              Text('Optional. Never required to race.',
                  style: BmText.body(12)),
              const SizedBox(height: 14),
              BmStatusBanner(controller: controller),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BmPanel(
                        color: BmColors.gold,
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium_rounded,
                                color: BmColors.gold, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    active ? 'YOU ARE A VIP' : 'NOT A MEMBER',
                                    style: BmText.title(15,
                                        color: BmColors.gold),
                                  ),
                                  Text(
                                    controller.entitlement.statusLabel,
                                    style: BmText.body(11,
                                        color: BmColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('CHOOSE A PLAN', style: BmText.label(11)),
                      const SizedBox(height: 10),
                      _PlanCard(
                        title: 'Monthly',
                        product: monthly,
                        selected: _selected == VipPeriod.monthly,
                        onTap: () =>
                            setState(() => _selected = VipPeriod.monthly),
                      ),
                      const SizedBox(height: 10),
                      _PlanCard(
                        title: 'Annual',
                        product: annual,
                        selected: _selected == VipPeriod.annual,
                        onTap: () =>
                            setState(() => _selected = VipPeriod.annual),
                      ),
                      const SizedBox(height: 16),
                      Text('WHAT YOU GET', style: BmText.label(11)),
                      const SizedBox(height: 8),
                      const _BenefitList(compact: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (active)
                BmButton(
                  label: 'MANAGE MEMBERSHIP',
                  style: BmButtonStyle.outline,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MembershipManagementScreen(),
                    ),
                  ),
                )
              else
                BmButton(
                  label: controller.purchaseState == PurchaseState.purchasing
                      ? 'CONTACTING STORE…'
                      : 'BECOME A VIP',
                  style: BmButtonStyle.gold,
                  icon: Icons.workspace_premium_rounded,
                  onPressed: controller.purchaseState == PurchaseState.purchasing
                      ? null
                      : () => _buy(controller),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BmButton(
                      label: 'RESTORE PURCHASES',
                      height: 44,
                      fontSize: 12,
                      style: BmButtonStyle.outline,
                      onPressed: controller.restorePurchases,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BmButton(
                      label: 'BENEFITS',
                      height: 44,
                      fontSize: 12,
                      style: BmButtonStyle.outline,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const VipBenefitsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final StoreProduct? product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = product == null
        ? 'Store not connected'
        : product!.hasPrice
            ? '${product!.priceString} / ${title.toLowerCase() == 'monthly' ? 'month' : 'year'}'
            : 'Unavailable';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(colors: [
                    Color(0xFF3A2A05),
                    Color(0xFF211703),
                  ])
                : BmGradients.panel,
            border: Border.all(
              color: selected ? BmColors.gold : BmColors.panelEdge,
              width: selected ? 2 : 1.2,
            ),
            boxShadow: selected
                ? bmGlow(BmColors.gold, blur: 18, opacity: 0.4)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? BmColors.gold : BmColors.muted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: BmText.title(14)),
              ),
              Text(
                price,
                style: BmText.body(13, color: BmColors.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitList extends StatelessWidget {
  const _BenefitList({this.compact = false});

  final bool compact;

  static const _benefits = <(IconData, String)>[
    (Icons.block_rounded, 'Remove ordinary advertising'),
    (Icons.album_rounded, 'Exclusive profile borders and badges'),
    (Icons.directions_run_rounded, 'Premium racing animations'),
    (Icons.face_retouching_natural_rounded, 'Exclusive avatar accessories'),
    (Icons.badge_rounded, 'Custom VIP nameplates'),
    (Icons.insights_rounded, 'Enhanced player statistics'),
    (Icons.refresh_rounded, 'Regularly refreshed VIP cosmetic collection'),
    (Icons.emoji_events_rounded, 'VIP-only cosmetic challenges'),
    (Icons.palette_rounded, 'Optional VIP visual themes'),
  ];

  @override
  Widget build(BuildContext context) {
    final shown = compact ? _benefits.take(5).toList() : _benefits;
    return Column(
      children: [
        for (final (icon, text) in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: BmColors.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: BmText.body(12))),
              ],
            ),
          ),
      ],
    );
  }
}

/// Full benefits page.
class VipBenefitsScreen extends StatelessWidget {
  const VipBenefitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          const _VipHeader(title: 'VIP BENEFITS'),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: BmPanel(
                color: BmColors.gold,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BenefitList(),
                    const SizedBox(height: 8),
                    Text(
                      'VIP never gives a scoring advantage in ranked play, and '
                      'is never required to join a multiplayer race. VIP players '
                      'may still watch optional rewarded adverts to earn coins.',
                      style: BmText.body(11, color: BmColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manage: status, expiry, cancel path, restore.
class MembershipManagementScreen extends StatelessWidget {
  const MembershipManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final entitlement = controller.entitlement;
        final expires = entitlement.expiresAt;
        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _VipHeader(title: 'MEMBERSHIP'),
              const SizedBox(height: 14),
              BmStatusBanner(controller: controller),
              BmPanel(
                color: BmColors.gold,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: BmText.label(10)),
                    Text(entitlement.statusLabel,
                        style: BmText.title(14, color: Colors.white)),
                    const SizedBox(height: 10),
                    Text('Plan', style: BmText.label(10)),
                    Text(
                      entitlement.productId ?? '—',
                      style: BmText.body(12),
                    ),
                    const SizedBox(height: 10),
                    Text('Expires', style: BmText.label(10)),
                    Text(
                      expires == null
                          ? '—'
                          : expires.toLocal().toString().split('.').first,
                      style: BmText.body(12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BmPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verification', style: BmText.label(10)),
                    const SizedBox(height: 4),
                    Text(
                      switch (entitlement.source) {
                        EntitlementSource.storeVerified =>
                          'Confirmed by the store.',
                        EntitlementSource.storeNotConfigured =>
                          'The store is not connected in this build, so membership cannot be verified here.',
                        EntitlementSource.validationFailed =>
                          'The store could not be reached. Membership stays locked until it confirms.',
                      },
                      style: BmText.body(12),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              BmButton(
                label: 'REFRESH STATUS',
                style: BmButtonStyle.cyan,
                onPressed: controller.refreshEntitlement,
              ),
              const SizedBox(height: 8),
              BmButton(
                label: 'MANAGE IN STORE',
                style: BmButtonStyle.outline,
                onPressed: controller.openManageSubscription,
              ),
              const SizedBox(height: 8),
              BmButton(
                label: 'RESTORE PURCHASES',
                style: BmButtonStyle.outline,
                onPressed: controller.restorePurchases,
              ),
              const SizedBox(height: 8),
              BmButton(
                label: 'PURCHASE HISTORY',
                style: BmButtonStyle.outline,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PurchaseHistoryScreen(),
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

/// Every store transaction the player has made.
class PurchaseHistoryScreen extends StatelessWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final records = controller.history;
        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _VipHeader(title: 'PURCHASE HISTORY'),
              const SizedBox(height: 14),
              BmStatusBanner(controller: controller),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(
                          controller.store.isConfigured
                              ? 'No purchases yet.'
                              : 'The store is not connected in this build.',
                          style:
                              BmText.body(13, color: BmColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return BmPanel(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  record.revoked
                                      ? Icons.restart_alt_rounded
                                      : Icons.receipt_long_rounded,
                                  color: record.revoked
                                      ? BmColors.red
                                      : BmColors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(record.productId,
                                          style: BmText.title(12)),
                                      Text(
                                        record.purchasedAt
                                            .toLocal()
                                            .toString()
                                            .split('.')
                                            .first,
                                        style: BmText.body(10,
                                            color: BmColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  record.revoked
                                      ? 'REFUNDED'
                                      : record.priceString.isEmpty
                                          ? 'OWNED'
                                          : record.priceString,
                                  style: BmText.label(10,
                                      color: record.revoked
                                          ? BmColors.red
                                          : BmColors.gold),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
