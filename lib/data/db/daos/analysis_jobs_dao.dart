import 'package:drift/drift.dart';

import '../../../core/enums.dart';
import '../database.dart';
import '../tables.dart';

part 'analysis_jobs_dao.g.dart';

@DriftAccessor(tables: [AnalysisJobs])
class AnalysisJobsDao extends DatabaseAccessor<AppDatabase>
    with _$AnalysisJobsDaoMixin {
  AnalysisJobsDao(super.db);

  /// The most recent job for a room, whatever its state.
  Stream<AnalysisJob?> watchLatestForRoom(String roomId) => (select(analysisJobs)
        ..where((j) => j.roomId.equals(roomId))
        ..orderBy([(j) => OrderingTerm.desc(j.createdAt)])
        ..limit(1))
      .watchSingleOrNull();

  Future<AnalysisJob?> getJob(String id) =>
      (select(analysisJobs)..where((j) => j.id.equals(id))).getSingleOrNull();

  /// A queued or running job for the room, if any.
  Future<AnalysisJob?> activeForRoom(String roomId) => (select(analysisJobs)
        ..where((j) =>
            j.roomId.equals(roomId) &
            j.status.isIn([AnalysisJobStatus.queued.name, AnalysisJobStatus.running.name]))
        ..limit(1))
      .getSingleOrNull();

  Future<List<AnalysisJob>> queued() => (select(analysisJobs)
        ..where((j) => j.status.equalsValue(AnalysisJobStatus.queued))
        ..orderBy([(j) => OrderingTerm.asc(j.createdAt)]))
      .get();

  Future<void> insertJob(AnalysisJobsCompanion job) => into(analysisJobs).insert(job);

  Future<void> updateJob(String id, AnalysisJobsCompanion changes) =>
      (update(analysisJobs)..where((j) => j.id.equals(id)))
          .write(changes.copyWith(updatedAt: Value(DateTime.now())));

  /// Crash recovery on start: a job left in `running` never finished.
  Future<int> resetStaleRunning() =>
      (update(analysisJobs)..where((j) => j.status.equalsValue(AnalysisJobStatus.running)))
          .write(AnalysisJobsCompanion(
        status: const Value(AnalysisJobStatus.queued),
        updatedAt: Value(DateTime.now()),
      ));
}
