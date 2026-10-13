import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/env.dart';
import 'purchases/purchases_gateway.dart';

part 'entitlement.g.dart';

/// Free vs Pro (spec §7). Fed by the store through [PurchasesGateway]; the
/// provider is the single place the UI asks.
enum Entitlement {
  free,
  pro;

  bool get isPro => this == Entitlement.pro;
}

@Riverpod(keepAlive: true)
PurchasesGateway purchasesGateway(Ref ref) => Env.revenueCatApiKey.isEmpty
    ? UnavailablePurchasesGateway()
    : RevenueCatGateway(apiKey: Env.revenueCatApiKey);

@Riverpod(keepAlive: true)
class CurrentEntitlement extends _$CurrentEntitlement {
  StreamSubscription<bool>? _sub;

  @override
  Entitlement build() {
    final gateway = ref.watch(purchasesGatewayProvider);
    _sub = gateway.proUpdates.listen(
      (isPro) => state = isPro ? Entitlement.pro : Entitlement.free,
    );
    ref.onDispose(() => _sub?.cancel());
    return Entitlement.free;
  }

  /// Direct override: purchase results, restore, and the debug toggle.
  void set(Entitlement value) => state = value;

  Future<PurchaseOutcome> buy(ProOffer offer) async {
    final outcome = await ref.read(purchasesGatewayProvider).buy(offer);
    if (outcome == PurchaseOutcome.pro) state = Entitlement.pro;
    return outcome;
  }

  Future<PurchaseOutcome> restore() async {
    final outcome = await ref.read(purchasesGatewayProvider).restore();
    state = outcome == PurchaseOutcome.pro ? Entitlement.pro : Entitlement.free;
    return outcome;
  }
}
