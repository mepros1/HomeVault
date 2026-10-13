import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/api_errors.dart';
import '../../data/backup/report_backup_client.dart' show CloudBackup;
import '../../data/providers.dart';
import '../../data/settings/settings.dart';
import '../../l10n/app_localizations.dart';
import 'report_providers.dart';

/// "In the cloud" block of the report screen: what the server holds for
/// this device, download / delete, and the transfer-code flow that moves
/// backups to a new phone.
class CloudBackupSection extends ConsumerStatefulWidget {
  const CloudBackupSection({super.key});

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final enabled = ref.watch(cloudBackupEnabledProvider);
    final backups = ref.watch(cloudBackupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.cloudBackupsHeader, style: theme.textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.retry,
              onPressed: () => ref.invalidate(cloudBackupsProvider),
            ),
          ],
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.cloudBackupOff, style: theme.textTheme.bodySmall),
          ),
        switch (backups) {
          AsyncData(:final value) when value.isEmpty =>
            Text(l10n.cloudNone, style: theme.textTheme.bodySmall),
          AsyncData(:final value) => Column(
              children: [for (final b in value) _tile(context, b)],
            ),
          AsyncError() => Text(l10n.cloudUnavailable, style: theme.textTheme.bodySmall),
          _ => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
        },
        if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _showTransferCode,
              icon: const Icon(Icons.phonelink_setup_outlined),
              label: Text(l10n.transferCodeButton),
            ),
            TextButton(
              onPressed: _busy ? null : _enterCode,
              child: Text(l10n.enterCodeButton),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, CloudBackup b) {
    final l10n = AppLocalizations.of(context)!;
    final money = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0);
    final size = b.sizeBytes >= 1024 * 1024
        ? '${(b.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(b.sizeBytes / 1024).round()} KB';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_outlined),
      title: Text(DateFormat.yMMMd().add_Hm().format(b.generatedAt.toLocal())),
      subtitle: Text(
        '${l10n.itemsRecognised(b.itemCount)} · ${l10n.estimateRange(money.format(b.totalLow), money.format(b.totalHigh))} · $size',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: l10n.cloudDownload,
            onPressed: _busy ? null : () => _download(b),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.delete,
            onPressed: _busy ? null : () => _run(() => ref.read(reportBackupClientProvider).delete(b.id)),
          ),
        ],
      ),
    );
  }

  Future<void> _download(CloudBackup b) => _run(() async {
        final bytes = await ref.read(reportBackupClientProvider).download(b.id);
        final dir = Directory(p.join((await getTemporaryDirectory()).path, 'cloud'));
        await dir.create(recursive: true);
        final file = File(p.join(dir.path, b.fileName));
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
        );
      });

  Future<void> _showTransferCode() => _run(() async {
        final l10n = AppLocalizations.of(context)!;
        final code = await ref.read(reportBackupClientProvider).transferCode();
        if (!mounted) return;
        final minutes = code.expiresAt.difference(DateTime.now()).inMinutes.clamp(1, 60);
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.transferCodeTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '${code.code.substring(0, 4)}-${code.code.substring(4)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 12),
                Text(l10n.transferCodeBody(minutes)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.close)),
            ],
          ),
        );
      });

  Future<void> _enterCode() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.enterCodeTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: l10n.enterCodeLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.enterCodeButton),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    await _run(() async {
      final moved = await ref.read(reportBackupClientProvider).claim(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transferDone(moved))));
    });
  }

  /// Runs a cloud action with the busy indicator, maps errors to a snackbar
  /// and refreshes the list afterwards.
  Future<void> _run(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await action();
    } on TransferCodeInvalidException {
      _snack(l10n.transferInvalid);
    } on BackupLimitException {
      _snack(l10n.cloudBackupLimit);
    } on ApiException {
      _snack(l10n.cloudUnavailable);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(cloudBackupsProvider);
      }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
