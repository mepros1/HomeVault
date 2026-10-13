import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'reports_dao.g.dart';

@DriftAccessor(tables: [Reports])
class ReportsDao extends DatabaseAccessor<AppDatabase> with _$ReportsDaoMixin {
  ReportsDao(super.db);

  Stream<List<Report>> watchForHome(String homeId) => (select(reports)
        ..where((r) => r.homeId.equals(homeId))
        ..orderBy([(r) => OrderingTerm.desc(r.generatedAt)]))
      .watch();

  Future<void> insertReport(ReportsCompanion report) => into(reports).insert(report);

  Future<Report?> getReport(String id) =>
      (select(reports)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// PDFs that never reached the cloud backup, oldest first.
  Future<List<Report>> pendingBackup() => (select(reports)
        ..where((r) => r.backedUpAt.isNull())
        ..orderBy([(r) => OrderingTerm.asc(r.generatedAt)]))
      .get();

  Future<void> markBackedUp(String id, DateTime at) =>
      (update(reports)..where((r) => r.id.equals(id)))
          .write(ReportsCompanion(backedUpAt: Value(at)));

  Future<int> deleteReport(String id) =>
      (delete(reports)..where((r) => r.id.equals(id))).go();
}
