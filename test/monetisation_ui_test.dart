import 'package:buzz_masters/bm/monetisation/bootstrap.dart';
import 'package:buzz_masters/bm/monetisation/controller.dart';
import 'package:buzz_masters/bm/monetisation/models.dart';
import 'package:buzz_masters/bm/monetisation/rules.dart';
import 'package:buzz_masters/bm/monetisation/ui/rewards_screen.dart';
import 'package:buzz_masters/bm/monetisation/ui/shop_screen.dart';
import 'package:buzz_masters/bm/monetisation/ui/vip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'monetisation/fakes.dart';

/// Builds a controller, registers it for the screens and loads its state, the
/// same way [BmMonetisation.ensure] does in the app.
Future<MonetisationController> setupController({
  FakeStore? store,
  FakeBackend? backend,
  FakeAds? ads,
}) async {
  final controller = MonetisationController(
    store: store ?? FakeStore(),
    backend: backend ?? FakeBackend(),
    ads: ads ?? FakeAds(),
    account: const BmGameAccount('acct_widget_test_01'),
    clock: () => DateTime(2026, 10, 29, 12, 0, 0),
  );
  BmMonetisation.debugOverride(controller);
  await controller.load();
  return controller;
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The studio background animates forever, so `pumpAndSettle` would never
/// return — every screen pump uses bounded frames like the existing suite.
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(wrap(screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 360));
}

void main() {
  tearDown(BmMonetisation.debugReset);

  testWidgets('shop shows real store prices and owned state', (tester) async {
    await setupController();
    await pumpScreen(tester, const ShopScreen());

    // The default category is bundles, priced by the store.
    expect(find.text('COSMETIC SHOP'), findsOneWidget);
    expect(find.text('Starter Bundle'), findsOneWidget);
    expect(find.text('£1.99'), findsOneWidget);

    // Nothing is owned yet, so no EQUIP button appears.
    expect(find.text('EQUIP'), findsNothing);
    expect(find.text('DETAILS'), findsWidgets);
  });

  testWidgets('a bundle purchase marks it owned and equippable',
      (tester) async {
    final controller = await setupController();
    await pumpScreen(tester, const ShopScreen());

    final result = await controller.buyBundle(ProductIds.starterBundle);
    expect(result.state, PurchaseState.success);
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('OWNED'), findsWidgets);
    expect(find.text('EQUIP'), findsOneWidget);
  });

  testWidgets('a store with no catalogue never shows a price', (tester) async {
    await setupController(store: FakeStore(configured: false));
    await pumpScreen(tester, const ShopScreen());

    expect(find.text('Store not connected'), findsWidgets);
    expect(find.text('£1.99'), findsNothing);
  });

  testWidgets('VIP paywall offers both plans with store prices',
      (tester) async {
    await setupController();
    await pumpScreen(tester, const VipMembershipScreen());

    expect(find.text('BUZZ MASTERS VIP'), findsOneWidget);
    expect(find.text('£3.99 / month'), findsOneWidget);
    expect(find.text('£29.99 / year'), findsOneWidget);
    expect(find.text('BECOME A VIP'), findsOneWidget);
    expect(find.text('RESTORE PURCHASES'), findsOneWidget);
  });

  testWidgets('VIP paywall says so when the store is not connected',
      (tester) async {
    await setupController(store: FakeStore(configured: false));
    await pumpScreen(tester, const VipMembershipScreen());

    expect(find.text('Store not connected'), findsWidgets);
    expect(find.text('BECOME A VIP'), findsOneWidget);
  });

  testWidgets('rewards centre shows the daily cap and balance', (tester) async {
    await setupController();
    await pumpScreen(tester, const DailyRewardsScreen());

    expect(find.text('REWARDS CENTRE'), findsOneWidget);
    expect(find.text('COIN BALANCE'), findsOneWidget);
    expect(find.textContaining('0 of 5 used today'), findsOneWidget);
    expect(find.text('CLAIM'), findsOneWidget);
  });

  testWidgets('the rewards centre shows a claimed balance', (tester) async {
    final controller = await setupController();
    await controller.claimDailyReward();

    await pumpScreen(tester, const DailyRewardsScreen());

    expect(find.text('50'), findsOneWidget);
    expect(find.text('Daily reward'), findsWidgets);
    expect(find.text('+50'), findsWidgets);
  });
}
