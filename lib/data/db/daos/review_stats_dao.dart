import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'review_stats_dao.g.dart';

/// Counters only (spec §10): how users treat what each prompt version
/// produced. Never stores item content.
@DriftAccessor(tables: [ReviewStats])
class ReviewStatsDao extends DatabaseAccessor<AppDatabase> with _$ReviewStatsDaoMixin {
  ReviewStatsDao(super.db);

  static const String unknownVersion = 'unknown';

  Future<void> bump(
    String? promptVersion, {
    int accepted = 0,
    int edited = 0,
    int deleted = 0,
  }) async {
    final version = promptVersion ?? unknownVersion;
    await into(reviewStats).insert(
      ReviewStatsCompanion.insert(promptVersion: version),
      mode: InsertMode.insertOrIgnore,
    );
    await (update(reviewStats)..where((s) => s.promptVersion.equals(version))).write(
      ReviewStatsCompanion.custom(
        accepted: reviewStats.accepted + Constant(accepted),
        edited: reviewStats.edited + Constant(edited),
        deleted: reviewStats.deleted + Constant(deleted),
      ),
    );
  }

  Future<List<ReviewStat>> all() => select(reviewStats).get();

  /// Rows whose counters moved since the last successful upload.
  Future<List<ReviewStat>> unsynced() => (select(reviewStats)
        ..where(
          (s) =>
              s.accepted.isNotExp(s.syncedAccepted) |
              s.edited.isNotExp(s.syncedEdited) |
              s.deleted.isNotExp(s.syncedDeleted),
        ))
      .get();

  /// Records the exact values that were uploaded, so bumps that happened
  /// during the request are reported next time.
  Future<void> markSynced(Iterable<ReviewStat> uploaded) => batch((b) {
        for (final s in uploaded) {
          b.update(
            reviewStats,
            ReviewStatsCompanion(
              syncedAccepted: Value(s.accepted),
              syncedEdited: Value(s.edited),
              syncedDeleted: Value(s.deleted),
            ),
            where: (t) => t.promptVersion.equals(s.promptVersion),
          );
        }
      });
}
