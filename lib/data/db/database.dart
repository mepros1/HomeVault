import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/enums.dart';
import 'daos/analysis_jobs_dao.dart';
import 'daos/captures_dao.dart';
import 'daos/homes_dao.dart';
import 'daos/items_dao.dart';
import 'daos/reports_dao.dart';
import 'daos/review_stats_dao.dart';
import 'daos/rooms_dao.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Homes, Rooms, Captures, Items, Attachments, Reports, AnalysisJobs, ReviewStats],
  daos: [HomesDao, RoomsDao, CapturesDao, ItemsDao, AnalysisJobsDao, ReviewStatsDao, ReportsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX idx_rooms_home ON rooms (home_id, order_index)',
          );
          await customStatement(
            'CREATE INDEX idx_captures_room ON captures (room_id)',
          );
          await customStatement('CREATE INDEX idx_items_room ON items (room_id)');
          await customStatement(
            'CREATE INDEX idx_attachments_item ON attachments (item_id)',
          );
          await customStatement(
            'CREATE INDEX idx_jobs_status ON analysis_jobs (status, created_at)',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(reviewStats, reviewStats.syncedAccepted);
            await m.addColumn(reviewStats, reviewStats.syncedEdited);
            await m.addColumn(reviewStats, reviewStats.syncedDeleted);
          }
          if (from < 3) {
            await m.addColumn(reports, reports.backedUpAt);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'homevault', native: const DriftNativeOptions());
}
