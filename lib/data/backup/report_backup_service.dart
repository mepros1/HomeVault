import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/api_errors.dart';
import '../db/database.dart';
import 'report_backup_client.dart';

/// Copies generated PDFs to the server when cloud backup is on. Uploads
/// that fail stay pending (`reports.backed_up_at` null) and are retried at
/// the next app start or export.
class ReportBackupService {
  ReportBackupService(
    this._db, {
    required ReportBackupClient client,
    required Future<Directory> Function() baseDir,
    required bool Function() enabled,
    DateTime Function()? clock,
  })  : _client = client,
        _baseDir = baseDir,
        _enabled = enabled,
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final ReportBackupClient _client;
  final Future<Directory> Function() _baseDir;
  final bool Function() _enabled;
  final DateTime Function() _clock;

  Future<void>? _inFlight;

  /// Uploads every report that has not reached the cloud yet. Stops at the
  /// first network failure or full backup; other errors skip the report.
  Future<void> backupPending() {
    return _inFlight ??= _backupPending().whenComplete(() => _inFlight = null);
  }

  Future<void> _backupPending() async {
    if (!_enabled()) return;
    for (final report in await _db.reportsDao.pendingBackup()) {
      try {
        await _upload(report);
      } on NetworkException {
        return;
      } on BackupLimitException {
        return;
      } on ApiException catch (e) {
        debugPrint('backup of ${report.id} failed: $e');
      }
    }
  }

  /// Uploads one report right after it was generated. Returns false when
  /// the file did not reach the server (it stays pending).
  Future<bool> backup(Report report) async {
    if (!_enabled()) return false;
    try {
      await _upload(report);
      return true;
    } on ApiException catch (e) {
      debugPrint('backup of ${report.id} failed: $e');
      return false;
    }
  }

  Future<void> _upload(Report report) async {
    final file = File(p.join((await _baseDir()).path, report.pdfPath));
    if (!await file.exists()) return;
    await _client.upload(
      id: report.id,
      fileName: p.basename(report.pdfPath),
      generatedAt: report.generatedAt,
      itemCount: report.itemCount,
      totalLow: report.totalLow,
      totalHigh: report.totalHigh,
      pdf: await file.readAsBytes(),
    );
    await _db.reportsDao.markBackedUp(report.id, _clock());
  }
}
