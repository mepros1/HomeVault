import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analysis/analysis_queue.dart';
import '../../data/analysis/analysis_runner.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/settings/settings.dart';
import '../capture/capture_providers.dart';

// Hand-written providers: they carry Drift row classes (see CLAUDE.md).

final analysisRunnerProvider = Provider<AnalysisRunner>(
  (ref) => AnalysisRunner(
    db: ref.watch(appDatabaseProvider),
    captures: ref.watch(captureStoreProvider),
    client: ref.watch(analyzeRoomClientProvider),
    highValueThreshold: ref.watch(highValueThresholdProvider),
  ),
);

final analysisQueueProvider = Provider<AnalysisQueue>((ref) {
  final queue = AnalysisQueue(
    ref.watch(appDatabaseProvider),
    ref.watch(analysisRunnerProvider),
    connectivity: Connectivity().onConnectivityChanged,
  );
  ref.onDispose(queue.dispose);
  return queue;
});

final latestJobForRoomProvider = StreamProvider.family<AnalysisJob?, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).analysisJobsDao.watchLatestForRoom(roomId),
);

/// Review-screen order: est_high DESC (spec §3.4), done in SQL.
final itemsForRoomProvider = StreamProvider.family<List<Item>, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).itemsDao.watchItemsForRoom(roomId),
);
