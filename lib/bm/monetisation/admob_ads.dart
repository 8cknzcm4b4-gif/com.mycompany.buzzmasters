/// Google AdMob adapter for [AdsGateway].
///
/// Rewarded video only, and only ever started by an explicit user action.
/// The callback here reports that a reward *event* happened — the coins are
/// granted by the backend after it validates the event, never from this file.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'gateways.dart';

class AdMobRewardedAds implements AdsGateway {
  AdMobRewardedAds({required this.rewardedAdUnitId, this.userId = ''});

  /// Sent to AdMob server-side verification so the signed callback names the
  /// player to credit (the Supabase user id).
  final String userId;

  /// Google's TEST unit id while developing. A production unit id must be
  /// supplied through configuration before live adverts are enabled.
  final String rewardedAdUnitId;

  bool _initialised = false;
  RewardedAd? _pending;
  String _lastEventId = '';

  /// AdMob has no web SDK, so web builds report adverts as unavailable.
  @override
  bool get isConfigured => !kIsWeb && rewardedAdUnitId.trim().isNotEmpty;

  @override
  bool get isRewardedReady => _pending != null;

  /// Call once at start-up. Safe to repeat.
  Future<void> initialise() async {
    if (!isConfigured || _initialised) return;
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
    } catch (_) {
      _initialised = false;
    }
  }

  @override
  Future<bool> loadRewarded() async {
    if (!isConfigured || !_initialised) return false;
    if (_pending != null) return true;
    final completer = Completer<bool>();
    try {
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _pending = ad;
            if (!completer.isCompleted) completer.complete(true);
          },
          onAdFailedToLoad: (error) {
            _pending = null;
            if (!completer.isCompleted) completer.complete(false);
          },
        ),
      );
    } catch (_) {
      return false;
    }
    return completer.future;
  }

  @override
  Future<AdWatchResult> showRewarded() async {
    final ad = _pending;
    if (ad == null || !isConfigured) {
      return const AdWatchResult.notConfigured();
    }
    _pending = null;
    final completer = Completer<AdWatchResult>();
    final eventId =
        'ad-${DateTime.now().toUtc().microsecondsSinceEpoch}-${ad.hashCode}';
    _lastEventId = eventId;
    try {
      if (userId.isNotEmpty) {
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(userId: userId, customData: eventId),
        );
      }
      await ad.show(onUserEarnedReward: (fullAd, reward) {
        if (!completer.isCompleted) {
          completer.complete(AdWatchResult(
            completed: reward.amount > 0,
            eventId: eventId,
            // The provider reported a completed, quantified reward. Server
            // side verification (AdMob SSV) still has to confirm it.
            signatureValid: reward.amount > 0,
            message: 'Advertisement completed.',
          ));
        }
      });
      // Some platform versions never invoke the callback when dismissed.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          completer.complete(const AdWatchResult.dismissed());
        }
      });
    } catch (error) {
      return AdWatchResult(
        completed: false,
        message: 'Advertisement could not be shown: $error',
      );
    }
    ad.dispose();
    return completer.future;
  }

  /// The id of the last advert event, kept for diagnostics.
  String get lastEventId => _lastEventId;
}
