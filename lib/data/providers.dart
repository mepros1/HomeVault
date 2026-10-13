import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/env.dart';
import 'api/analyze_room_client.dart';
import 'auth/session.dart';
import 'backup/report_backup_client.dart';
import 'db/database.dart';
import 'integrity/app_check.dart';
import 'stats/review_stats_uploader.dart';

part 'providers.g.dart';

/// Play Integrity when a project number is compiled in, otherwise a no-op.
@Riverpod(keepAlive: true)
AppCheck appCheck(Ref ref) {
  if (Env.playIntegrityProjectNumber <= 0) return const NoopAppCheck();
  return PlayIntegrityAppCheck(cloudProjectNumber: Env.playIntegrityProjectNumber);
}

@Riverpod(keepAlive: true)
ReportBackupClient reportBackupClient(Ref ref) {
  final session = ref.watch(sessionProvider.notifier);
  final client = ReportBackupClient(
    baseEndpoint: Env.backupsEndpoint,
    accessToken: session.accessToken,
    refreshAccessToken: session.reissueToken,
  );
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
ReviewStatsUploader reviewStatsUploader(Ref ref) {
  final session = ref.watch(sessionProvider.notifier);
  final uploader = ReviewStatsUploader(
    ref.watch(appDatabaseProvider),
    endpoint: Env.reviewStatsEndpoint,
    accessToken: session.accessToken,
    refreshAccessToken: session.reissueToken,
  );
  ref.onDispose(uploader.close);
  return uploader;
}

/// Single app-wide database instance. Overridden in tests with an in-memory
/// executor.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
AnalyzeRoomClient analyzeRoomClient(Ref ref) {
  final session = ref.watch(sessionProvider.notifier);
  final client = AnalyzeRoomClient(
    endpoint: Env.analyzeRoomEndpoint,
    accessToken: session.accessToken,
    refreshAccessToken: session.reissueToken,
    appCheck: ref.watch(appCheckProvider),
  );
  ref.onDispose(client.close);
  return client;
}
