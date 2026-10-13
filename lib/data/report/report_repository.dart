import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../entitlement.dart';
import '../media/capture_store.dart';
import 'csv_report.dart';
import 'pdf_report.dart';
import 'report_data.dart';

/// Thrown when a Free install asks for a Pro-only export (spec §7).
class ProRequired implements Exception {
  const ProRequired();
}

/// Builds report files under `<base>/reports/` and records PDFs in `reports`.
/// Paths in the table are relative to the base dir, like captures.
class ReportRepository {
  ReportRepository({
    required AppDatabase db,
    required CaptureStore captures,
    required PdfReportGenerator pdf,
    required Future<Directory> Function() baseDir,
    required Entitlement Function() entitlement,
    DateTime Function()? clock,
  })  : _db = db,
        _captures = captures,
        _pdf = pdf,
        _baseDir = baseDir,
        _entitlement = entitlement,
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final CaptureStore _captures;
  final PdfReportGenerator _pdf;
  final Future<Directory> Function() _baseDir;
  final Entitlement Function() _entitlement;
  final DateTime Function() _clock;

  Future<ReportData?> preview(String homeId) => ReportBuilder(_db).build(homeId, now: _clock());

  /// Free tier gets the watermark; Pro gets a clean file.
  Future<Report> generatePdf(String homeId) async {
    final data = await ReportBuilder(_db).build(homeId, now: _clock());
    if (data == null) throw StateError('home $homeId not found');

    final bytes = await _pdf.generate(
      data,
      watermark: !_entitlement().isPro,
      thumbOf: _thumbBytes,
    );

    final id = const Uuid().v4();
    final rel = p.posix.join('reports', fileName(data, id, 'pdf'));
    await _write(rel, bytes);

    final report = Report(
      id: id,
      homeId: homeId,
      generatedAt: data.generatedAt,
      pdfPath: rel,
      itemCount: data.itemCount,
      totalLow: data.totalLow,
      totalHigh: data.totalHigh,
    );
    await _db.reportsDao.insertReport(report.toCompanion(false));
    return report;
  }

  /// Returns the relative path of the CSV. Pro only.
  Future<String> generateCsv(String homeId) async {
    if (!_entitlement().isPro) throw const ProRequired();
    final data = await ReportBuilder(_db).build(homeId, now: _clock());
    if (data == null) throw StateError('home $homeId not found');
    final rel = p.posix.join('reports', fileName(data, const Uuid().v4(), 'csv'));
    await _write(rel, Uint8List.fromList(CsvReportGenerator().generate(data).codeUnits));
    return rel;
  }

  Future<void> deleteReport(Report report) async {
    final f = File(await absolutePath(report.pdfPath));
    if (await f.exists()) await f.delete();
    await _db.reportsDao.deleteReport(report.id);
  }

  Future<String> absolutePath(String relative) async =>
      p.join((await _baseDir()).path, relative);

  /// What the share sheet shows: `HomeVault-Our-flat-2026-09-21-3524c8d6.pdf`.
  static String fileName(ReportData data, String id, String ext) {
    final slug = data.home.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final day = data.generatedAt.toIso8601String().substring(0, 10);
    return 'HomeVault-${slug.isEmpty ? 'home' : slug}-$day-${id.substring(0, 8)}.$ext';
  }

  Future<void> _write(String rel, List<int> bytes) async {
    final base = await _baseDir();
    final file = File(p.join(base.path, rel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> _thumbBytes(Capture c) async {
    final f = await _captures.thumbFile(c);
    if (f == null || !await f.exists()) return null;
    return f.readAsBytes();
  }
}
