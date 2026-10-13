import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/env.dart';
import '../../data/entitlement.dart';
import '../../data/purchases/purchases_gateway.dart';
import '../../l10n/app_localizations.dart';

/// One-time Pro purchase (spec §7): unlimited rooms, clean PDF, CSV.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late final Future<ProOffer?> _offer = ref.read(purchasesGatewayProvider).currentOffer();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isPro = ref.watch(currentEntitlementProvider).isPro;
    final available = ref.watch(purchasesGatewayProvider).isAvailable;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.paywallTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.workspace_premium_outlined, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(l10n.paywallHeadline, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _Benefit(icon: Icons.meeting_room_outlined, text: l10n.paywallBenefitRooms),
          _Benefit(icon: Icons.picture_as_pdf_outlined, text: l10n.paywallBenefitPdf),
          _Benefit(icon: Icons.table_chart_outlined, text: l10n.paywallBenefitCsv),
          _Benefit(icon: Icons.lock_outline, text: l10n.paywallBenefitOnce),
          const SizedBox(height: 24),
          if (isPro)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.paywallAlreadyPro, textAlign: TextAlign.center),
              ),
            )
          else
            FutureBuilder<ProOffer?>(
              future: _offer,
              builder: (context, snapshot) {
                if (!available) {
                  return Text(l10n.paywallUnavailable,
                      style: theme.textTheme.bodyMedium, textAlign: TextAlign.center);
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final offer = snapshot.data;
                if (offer == null) {
                  return Text(l10n.paywallNoOffer,
                      style: theme.textTheme.bodyMedium, textAlign: TextAlign.center);
                }
                return FilledButton(
                  onPressed: _busy ? null : () => _buy(offer),
                  child: Text(l10n.paywallBuy(offer.priceString)),
                );
              },
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy || !available ? null : _restore,
            child: Text(l10n.restorePurchases),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 24),
          Text(Disclaimer.short, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(Env.privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l10n.privacyPolicy),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(ProOffer offer) async {
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(currentEntitlementProvider.notifier).buy(offer);
      _report(outcome, purchased: true);
    } catch (e) {
      _snack((l10n) => l10n.purchaseFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(currentEntitlementProvider.notifier).restore();
      _report(outcome, purchased: false);
    } catch (e) {
      _snack((l10n) => l10n.purchaseFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(PurchaseOutcome outcome, {required bool purchased}) {
    switch (outcome) {
      case PurchaseOutcome.pro:
        _snack((l10n) => l10n.purchaseSuccess);
        if (mounted && context.canPop()) context.pop();
      case PurchaseOutcome.notPro:
        _snack((l10n) => purchased ? l10n.purchaseFailed : l10n.restoreNothing);
      case PurchaseOutcome.cancelled:
        break;
    }
  }

  void _snack(String Function(AppLocalizations) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text(AppLocalizations.of(context)!))),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
