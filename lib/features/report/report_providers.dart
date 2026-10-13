import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/backup/report_backup_client.dart';
import '../../data/backup/report_backup_service.dart';
import '../../data/db/database.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../data/report/pdf_report.dart';
import '../../data/report/report_repository.dart';
import '../../data/settings/settings.dart';
import '../capture/capture_providers.dart';

// Hand-written providers: they carry Drift row classes (see CLAUDE.md).

/// Noto Sans covers far more scripts than the PDF core fonts, which matters
/// for user-typed item names.
Future<(pw.Font, pw.Font)> _loadFonts() async {
  final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  return (pw.Font.ttf(regular), pw.Font.ttf(bold));
}

final pdfReportGeneratorProvider = Provider<PdfReportGenerator>(
  (ref) => PdfReportGenerator(fonts: _loadFonts),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(
    db: ref.watch(appDatabaseProvider),
    captures: ref.watch(captureStoreProvider),
    pdf: ref.watch(pdfReportGeneratorProvider),
    baseDir: ref.watch(captureBaseDirProvider),
    entitlement: () => ref.read(currentEntitlementProvider),
  ),
);

final reportsForHomeProvider = StreamProvider.family<List<Report>, String>(
  (ref, homeId) => ref.watch(appDatabaseProvider).reportsDao.watchForHome(homeId),
);

final reportBackupServiceProvider = Provider<ReportBackupService>(
  (ref) => ReportBackupService(
    ref.watch(appDatabaseProvider),
    client: ref.watch(reportBackupClientProvider),
    baseDir: ref.watch(captureBaseDirProvider),
    enabled: () => ref.read(cloudBackupEnabledProvider),
  ),
);

/// What the server currently holds for this device. Refresh with
/// `ref.invalidate(cloudBackupsProvider)` after an upload, delete or claim.
final cloudBackupsProvider = FutureProvider.autoDispose<List<CloudBackup>>(
  (ref) => ref.watch(reportBackupClientProvider).list(),
);
