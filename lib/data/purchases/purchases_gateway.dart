import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// What the app can buy. One-time purchase in v1 (spec §7).
class ProOffer {
  const ProOffer({required this.priceString, required this.package});

  /// Localised price from the store, e.g. `$14.99`.
  final String priceString;

  /// Opaque handle passed back to [PurchasesGateway.buy].
  final Object package;
}

/// Outcome of a purchase or restore attempt.
enum PurchaseOutcome { pro, notPro, cancelled }

/// Thin seam over the RevenueCat SDK so the paywall and entitlement logic
/// can be tested without a store.
abstract interface class PurchasesGateway {
  /// True when a store connection exists (API key set, SDK configured).
  bool get isAvailable;

  /// Emits the current Pro state on configure and on every SDK update.
  Stream<bool> get proUpdates;

  /// [appUserId] is the app's device id, so the server-side RevenueCat
  /// webhook can map purchases to `devices.user_id` (see CLAUDE.md).
  Future<void> configure({String? appUserId});

  Future<ProOffer?> currentOffer();

  Future<PurchaseOutcome> buy(ProOffer offer);

  Future<PurchaseOutcome> restore();
}

/// RevenueCat implementation. The entitlement identifier must match the
/// RevenueCat dashboard; products are configured there, not in code.
class RevenueCatGateway implements PurchasesGateway {
  RevenueCatGateway({required this.apiKey, this.entitlementId = 'pro'});

  final String apiKey;
  final String entitlementId;
  final _updates = StreamController<bool>.broadcast();
  bool _configured = false;

  @override
  bool get isAvailable => _configured;

  @override
  Stream<bool> get proUpdates => _updates.stream;

  @override
  Future<void> configure({String? appUserId}) async {
    if (apiKey.isEmpty || _configured) return;
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(apiKey)..appUserID = appUserId);
      _configured = true;
      Purchases.addCustomerInfoUpdateListener((info) => _updates.add(_isPro(info)));
      _updates.add(_isPro(await Purchases.getCustomerInfo()));
    } on PlatformException catch (e) {
      debugPrint('RevenueCat configure failed: ${e.message}');
    }
  }

  @override
  Future<ProOffer?> currentOffer() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return null;
      final package = current.lifetime ??
          (current.availablePackages.isEmpty ? null : current.availablePackages.first);
      if (package == null) return null;
      return ProOffer(priceString: package.storeProduct.priceString, package: package);
    } on PlatformException catch (e) {
      debugPrint('RevenueCat offerings failed: ${e.message}');
      return null;
    }
  }

  @override
  Future<PurchaseOutcome> buy(ProOffer offer) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(offer.package as Package));
      return _isPro(result.customerInfo) ? PurchaseOutcome.pro : PurchaseOutcome.notPro;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      rethrow;
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    final info = await Purchases.restorePurchases();
    return _isPro(info) ? PurchaseOutcome.pro : PurchaseOutcome.notPro;
  }

  bool _isPro(CustomerInfo info) => info.entitlements.active.containsKey(entitlementId);
}

/// No API key: every store call is a no-op and the paywall explains that
/// purchases are unavailable in this build.
class UnavailablePurchasesGateway implements PurchasesGateway {
  @override
  bool get isAvailable => false;

  @override
  Stream<bool> get proUpdates => const Stream.empty();

  @override
  Future<void> configure({String? appUserId}) async {}

  @override
  Future<ProOffer?> currentOffer() async => null;

  @override
  Future<PurchaseOutcome> buy(ProOffer offer) async => PurchaseOutcome.notPro;

  @override
  Future<PurchaseOutcome> restore() async => PurchaseOutcome.notPro;
}

/// Test double with scripted outcomes.
class FakePurchasesGateway implements PurchasesGateway {
  FakePurchasesGateway({
    this.offer = const ProOffer(priceString: r'$14.99', package: 'pkg'),
    this.buyOutcome = PurchaseOutcome.pro,
    this.restoreOutcome = PurchaseOutcome.notPro,
  });

  ProOffer? offer;
  PurchaseOutcome buyOutcome;
  PurchaseOutcome restoreOutcome;
  final updates = StreamController<bool>.broadcast();
  int buys = 0;

  @override
  bool get isAvailable => true;

  @override
  Stream<bool> get proUpdates => updates.stream;

  String? configuredAppUserId;

  @override
  Future<void> configure({String? appUserId}) async {
    configuredAppUserId = appUserId;
  }

  @override
  Future<ProOffer?> currentOffer() async => offer;

  @override
  Future<PurchaseOutcome> buy(ProOffer offer) async {
    buys++;
    return buyOutcome;
  }

  @override
  Future<PurchaseOutcome> restore() async => restoreOutcome;
}
