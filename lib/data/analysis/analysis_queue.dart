import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../db/database.dart';
import 'analysis_runner.dart';

/// Persistent, sequential analysis queue (spec §3.3).
///
/// Jobs live in `analysis_jobs`, so they survive restarts and offline
/// periods. One job runs at a time; a transient failure stops the drain and
/// the next connectivity change, app start or manual retry resumes it.
class AnalysisQueue {
  AnalysisQueue(this._db, this._runner, {Stream<List<ConnectivityResult>>? connectivity})
      : _connectivity = connectivity;

  final AppDatabase _db;
  final AnalysisRunner _runner;
  final Stream<List<ConnectivityResult>>? _connectivity;

  Future<void>? _draining;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Call once at app start: recovers jobs interrupted by a crash, drains,
  /// and re-drains whenever the device comes back online.
  Future<void> start() async {
    await _db.analysisJobsDao.resetStaleRunning();
    _connectivitySub ??= _connectivity?.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(drain());
    });
    unawaited(drain());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Queues an analysis for the room, or returns the id of the one already
  /// queued or running. Overwrite rules are applied by the runner.
  Future<String> enqueue(String roomId) async {
    final active = await _db.analysisJobsDao.activeForRoom(roomId);
    if (active != null) return active.id;

    final id = const Uuid().v4();
    final now = DateTime.now();
    await _db.analysisJobsDao.insertJob(
      AnalysisJobsCompanion.insert(
        id: id,
        roomId: roomId,
        idempotencyKey: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
    unawaited(drain());
    return id;
  }

  /// Re-queues a failed job and starts draining.
  Future<void> retry(String jobId) async {
    await _db.analysisJobsDao.updateJob(
      jobId,
      const AnalysisJobsCompanion(
        status: Value(AnalysisJobStatus.queued),
        attempts: Value(0),
        lastError: Value(null),
      ),
    );
    await drain();
  }

  /// Runs queued jobs in order until the queue is empty or a transient
  /// failure says to wait. Concurrent callers share one drain.
  Future<void> drain() => _draining ??= _drain().whenComplete(() => _draining = null);

  Future<void> _drain() async {
    while (true) {
      final queued = await _db.analysisJobsDao.queued();
      if (queued.isEmpty) return;
      final outcome = await _runner.run(queued.first);
      if (outcome == JobOutcome.retryLater) return;
    }
  }
}
