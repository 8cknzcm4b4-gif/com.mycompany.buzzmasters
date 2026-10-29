/// RevenueCat adapter for [StoreGateway].
///
/// Native Apple/Google billing through the RevenueCat SDK. Configuration is
/// opt-in: without an API key this adapter reports itself unconfigured and
/// never pretends a purchase succeeded.
///
/// The SDK is imported with an `rc` prefix because it exports `StoreProduct`
/// and `PurchaseResult`, which collide with this app's own models.
library;

import 'dart:io' show Platform;

import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:url_launcher/url_launcher.dart';

import 'gateways.dart';
import 'models.dart';

class RevenueCatStore implements StoreGateway {
  RevenueCatStore({required this.apiKey, required this.appUserId});

  /// RevenueCat's **public** SDK key. The secret server key never ships in an
  /// app. Empty means "not configured".
  final String apiKey;

  /// The authenticated game account. One stable id per player so entitlements
  /// follow the player across devices.
  final String appUserId;

  bool _configured = false;

  @override
  bool get isConfigured => _configured;

  /// Configures the SDK. Safe to call twice.
  Future<void> configure() async {
    if (apiKey.trim().isEmpty || _configured) return;
    await rc.Purchases.setLogLevel(rc.LogLevel.warn);
    final configuration = rc.PurchasesConfiguration(apiKey)
      ..appUserID = appUserId;
    await rc.Purchases.configure(configuration);
    _configured = true;
  }

  StoreProduct _mapProduct(rc.StoreProduct product) {
    final isVip = product.identifier == ProductIds.vipMonthly ||
        product.identifier == ProductIds.vipAnnual;
    return StoreProduct(
      productId: product.identifier,
      title: product.title,
      priceString: product.priceString,
      currencyCode: product.currencyCode,
      kind: isVip
          ? StoreProductKind.subscription
          : StoreProductKind.nonConsumable,
      description: product.description,
      vipPeriod: product.identifier == ProductIds.vipMonthly
          ? VipPeriod.monthly
          : product.identifier == ProductIds.vipAnnual
              ? VipPeriod.annual
              : null,
    );
  }

  @override
  Future<List<StoreProduct>> products(List<String> productIds) async {
    if (!_configured) return const [];
    try {
      final offerings = await rc.Purchases.getOfferings();
      final byId = <String, StoreProduct>{};
      for (final package in offerings.current?.availablePackages ?? const []) {
        final mapped = _mapProduct(package.storeProduct);
        byId[mapped.productId] = mapped;
      }
      return [
        for (final id in productIds)
          if (byId[id] != null) byId[id]!,
      ];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<PurchaseResult> purchase(String productId) async {
    if (!_configured) {
      return const PurchaseResult.failure(
        'The store is not connected in this build.',
      );
    }
    try {
      final offerings = await rc.Purchases.getOfferings();
      rc.Package? match;
      for (final package in offerings.current?.availablePackages ?? const []) {
        if (package.storeProduct.identifier == productId) match = package;
      }
      if (match == null) {
        return const PurchaseResult.failure(
          'This product is not available on your store.',
        );
      }
      await rc.Purchases.purchase(rc.PurchaseParams.package(match));
      // The entitlement is re-read from the server afterwards, so this result
      // only records that the store completed the transaction.
      return PurchaseResult(state: PurchaseState.success, productId: productId);
    } on rc.PurchasesError catch (error) {
      if (error.code == rc.PurchasesErrorCode.purchaseCancelledError) {
        return const PurchaseResult.cancelled();
      }
      return PurchaseResult(
        state: PurchaseState.failed,
        message: 'Purchase failed: ${error.message}',
      );
    } catch (error) {
      return PurchaseResult(
        state: PurchaseState.failed,
        message: 'Purchase failed: $error',
      );
    }
  }

  @override
  Future<PurchaseResult> restore() async {
    if (!_configured) {
      return const PurchaseResult.failure(
        'The store is not connected in this build.',
      );
    }
    try {
      await rc.Purchases.restorePurchases();
      return const PurchaseResult(state: PurchaseState.restored);
    } catch (error) {
      return PurchaseResult(
        state: PurchaseState.failed,
        message: 'Restore failed: $error',
      );
    }
  }

  @override
  Future<VipEntitlement> entitlement(String appUserId) async {
    if (!_configured) {
      return const VipEntitlement(
        isActive: false,
        source: EntitlementSource.storeNotConfigured,
      );
    }
    try {
      final info = await rc.Purchases.getCustomerInfo();
      final active = info.entitlements.active[ProductIds.vipEntitlement];
      if (active == null || !active.isActive) {
        return const VipEntitlement.none();
      }
      final expires = active.expirationDate;
      return VipEntitlement(
        isActive: true,
        source: EntitlementSource.storeVerified,
        productId: active.productIdentifier,
        expiresAt: expires == null ? null : DateTime.tryParse(expires),
        willRenew: active.willRenew,
        period: active.productIdentifier == ProductIds.vipMonthly
            ? VipPeriod.monthly
            : VipPeriod.annual,
        validatedAt: DateTime.now(),
      );
    } catch (error) {
      return const VipEntitlement(
        isActive: false,
        source: EntitlementSource.validationFailed,
      );
    }
  }

  @override
  Future<List<PurchaseRecord>> history() async {
    if (!_configured) return const [];
    try {
      final info = await rc.Purchases.getCustomerInfo();
      final now = DateTime.now();
      final records = <PurchaseRecord>[];
      for (final entry in info.entitlements.active.entries) {
        final expires = entry.value.expirationDate;
        final parsed = expires == null ? null : DateTime.tryParse(expires);
        final revoked = parsed != null && parsed.isBefore(now);
        records.add(PurchaseRecord(
          transactionId: entry.key,
          productId: entry.value.productIdentifier,
          purchasedAt: now,
          revoked: revoked,
          state: PurchaseState.success,
        ));
      }
      return records;
    } catch (error) {
      return const [];
    }
  }

  @override
  Future<bool> openManageSubscription() async {
    // The SDK has no cross-platform entry point, so the store's own
    // subscription page is opened instead.
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse(
            'https://play.google.com/store/account/subscriptions',
          );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      return false;
    }
  }
}
