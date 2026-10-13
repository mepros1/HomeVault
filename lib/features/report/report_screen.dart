import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/env.dart';
import '../../core/router.dart';
import '../../data/db/database.dart';
import '../../data/entitlement.dart';
import '../../data/report/report_data.dart';
import '../../data/report/report_repository.dart';
import '../../l10n/app_localizations.dart';
import '../home/home_providers.dart';
import '../paywall/pro_dialog.dart';
import 'cloud_backup_section.dart';
import 'report_providers.dart';

/// Report hub (spec §3.7): live totals, PDF / CSV export, past reports.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final home = ref.watch(currentHomeProvider).value;
    if (home == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.reportTitle)));
    }
    final isPro = ref.watch(currentEntitlementProvider).isPro;
    final reports = ref.watch(reportsForHomeProvider(home.id)).value ?? const <Report>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<ReportData?>(
            future: ref.read(reportRepositoryProvider).preview(home.id),
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) return const LinearProgressIndicator();
              return _SummaryCard(data: data);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _exportPdf(home),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(l10n.exportPdf),
          ),
          if (!isPro)
            TextButton(
              onPressed: () => context.push(Routes.paywall),
              child: Text(l10n.freePdfWatermarkHint, style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _exportCsv(home),
            icon: Icon(isPro ? Icons.table_chart_outlined : Icons.lock_outline),
            label: Text(l10n.exportCsv),
          ),
          if (!isPro)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.proOnlyHint, style: Theme.of(context).textTheme.bodySmall),
            ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          const SizedBox(height: 24),
          Text(l10n.pastReports, style: Theme.of(context).textTheme.titleMedium),
          if (reports.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.noReportsYet, style: Theme.of(context).textTheme.bodySmall),
            )
          else
            for (final r in reports) _ReportTile(report: r),
          if (Env.isApiConfigured) ...[
            const SizedBox(height: 24),
            const CloudBackupSection(),
          ],
          const SizedBox(height: 24),
          Text(Disclaimer.short, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _exportPdf(Home home) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(reportRepositoryProvider);
      final report = await repo.generatePdf(home.id);
      if (Env.isApiConfigured) {
        // Fire and forget: a failed upload stays pending and is retried later.
        ref.read(reportBackupServiceProvider).backup(report).then((_) {
          if (mounted) ref.invalidate(cloudBackupsProvider);
        });
      }
      final path = await repo.absolutePath(report.pdfPath);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        subject: 'HomeVault inventory – ${home.name}',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv(Home home) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(reportRepositoryProvider);
    setState(() => _busy = true);
    try {
      final rel = await repo.generateCsv(home.id);
      final path = await repo.absolutePath(rel);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'text/csv')],
        subject: 'HomeVault inventory – ${home.name}',
      ));
    } on ProRequired {
      if (!mounted) return;
      await showProDialog(context, title: l10n.proRequiredTitle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final money = NumberFormat.simpleCurrency(name: data.currency, decimalDigits: 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.home.name, style: theme.textTheme.titleLarge),
            if (data.home.address != null) Text(data.home.address!),
            const SizedBox(height: 12),
            Text(
              l10n.estimateRange(money.format(data.totalLow), money.format(data.totalHigh)),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(l10n.reportSummaryLine(data.rooms.length, data.itemCount, data.captureCount)),
            if (data.unreviewedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.reportUnreviewedHint(data.unreviewedCount),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (data.highValueItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.reportHighValueLine(data.highValueItems.length)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final money = NumberFormat.simpleCurrency(name: Defaults.currency, decimalDigits: 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(DateFormat.yMMMd().add_Hm().format(report.generatedAt)),
      subtitle: Text(
        '${l10n.itemsRecognised(report.itemCount)} · ${l10n.estimateRange(money.format(report.totalLow), money.format(report.totalHigh))}'
        '${report.backedUpAt != null ? ' · ${l10n.backedUp}' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.share,
            onPressed: () async {
              final path = await ref.read(reportRepositoryProvider).absolutePath(report.pdfPath);
              await SharePlus.instance.share(
                ShareParams(files: [XFile(path, mimeType: 'application/pdf')]),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.delete,
            onPressed: () => ref.read(reportRepositoryProvider).deleteReport(report),
          ),
        ],
      ),
    );
  }
}
