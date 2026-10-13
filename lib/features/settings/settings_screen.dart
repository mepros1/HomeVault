import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/env.dart';
import '../../core/router.dart';
import '../../data/entitlement.dart';
import '../../data/settings/settings.dart';
import '../../l10n/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entitlement = ref.watch(currentEntitlementProvider);
    final threshold = ref.watch(highValueThresholdProvider);
    final money = NumberFormat.simpleCurrency(name: Defaults.currency, decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(entitlement.isPro ? l10n.planPro : l10n.planFree),
            subtitle: Text(entitlement.isPro ? l10n.planProHint : l10n.planFreeHint),
            trailing: entitlement.isPro ? null : const Icon(Icons.chevron_right),
            onTap: entitlement.isPro ? null : () => context.push(Routes.paywall),
          ),
          if (!entitlement.isPro)
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(l10n.restorePurchases),
              onTap: () => context.push(Routes.paywall),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(l10n.highValueThresholdTitle),
            subtitle: Text(l10n.highValueThresholdHint(money.format(threshold))),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editThreshold(context, ref, threshold),
          ),
          if (Env.isApiConfigured)
            SwitchListTile(
              secondary: const Icon(Icons.cloud_upload_outlined),
              title: Text(l10n.cloudBackupTitle),
              subtitle: Text(l10n.cloudBackupHint),
              value: ref.watch(cloudBackupEnabledProvider),
              onChanged: (v) => ref.read(cloudBackupEnabledProvider.notifier).set(v),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            subtitle: Text(Env.privacyPolicyUrl),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(
              Uri.parse(Env.privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            subtitle: Text(Disclaimer.short, style: theme.textTheme.bodySmall),
          ),
          if (kDebugMode) ...[
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('Debug: simulate Pro'),
              value: entitlement.isPro,
              onChanged: (v) => ref
                  .read(currentEntitlementProvider.notifier)
                  .set(v ? Entitlement.pro : Entitlement.free),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editThreshold(BuildContext context, WidgetRef ref, double current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: '${current.round()}');
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.highValueThresholdTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(prefixText: r'$ ', labelText: l10n.highValueThresholdLabel),
          onSubmitted: (v) => Navigator.of(context).pop(double.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text)),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value > 0) {
      await ref.read(highValueThresholdProvider.notifier).set(value);
    }
  }
}
