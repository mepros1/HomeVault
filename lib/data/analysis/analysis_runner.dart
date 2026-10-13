import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../api/analyze_room_client.dart';
import '../api/analyze_room_models.dart';
import '../api/api_errors.dart';
import '../api/idempotency.dart';
import '../db/database.dart';
import '../media/capture_store.dart';
import '../media/image_prep.dart';

/// What the queue should do with a job after one attempt.
enum JobOutcome {
  /// Items are in the database; the room is `analyzed`.
  done,

  /// Transient failure (offline, upstream). Job stays queued for a later drain.
  retryLater,

  /// Permanent failure; `last_error` holds a [JobError] code for the UI.
  failed,
}

/// Short codes stored in `analysis_jobs.last_error`; the UI maps them to text.
abstract final class JobError {
  static const String network = 'network';
  static const String upstream = 'upstream';
  static const String quota = 'quota';
  static const String unauthorized = 'unauthorized';
  static const String appCheck = 'app_check';
  static const String noItems = 'no_items';
  static const String tooLarge = 'too_large';
  static const String notEnoughPhotos = 'not_enough_photos';
  static const String roomMissing = 'room_missing';
  static const String other = 'other';

  /// Transient errors give up after this many attempts.
  static const int maxTransientAttempts = 5;
}

/// Executes one analysis job end to end (spec §3.3):
/// load captures → prepare uploads → call the server → write items.
class AnalysisRunner {
  AnalysisRunner({
    required AppDatabase db,
    required CaptureStore captures,
    required AnalyzeRoomClient client,
    this.highValueThreshold = Limits.defaultHighValueThreshold,
    DateTime Function()? clock,
  })  : _db = db,
        _captures = captures,
        _client = client,
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final CaptureStore _captures;
  final AnalyzeRoomClient _client;
  final double highValueThreshold;
  final DateTime Function() _clock;

  Future<JobOutcome> run(AnalysisJob job) async {
    final jobs = _db.analysisJobsDao;

    final room = await _db.roomsDao.getRoom(job.roomId);
    if (room == null) return _fail(job, JobError.roomMissing);

    final captures = await _db.capturesDao.forRoom(job.roomId);
    if (captures.length < Limits.minCapturesPerRoom) {
      return _fail(job, JobError.notEnoughPhotos);
    }
    final batch = captures.take(Limits.maxCapturesPerRoom).toList();

    final key = idempotencyKeyFor(batch.map((c) => c.sha256));
    await jobs.updateJob(
      job.id,
      AnalysisJobsCompanion(
        status: const Value(AnalysisJobStatus.running),
        attempts: Value(job.attempts + 1),
        idempotencyKey: Value(key),
        lastError: const Value(null),
      ),
    );

    final images = <PreparedImage>[];
    for (final c in batch) {
      images.add(await prepareForAnalysis(await _captures.readOriginal(c)));
    }

    final AnalyzeRoomResponse response;
    try {
      response = await _client.analyzeRoom(
        roomType: room.roomType == RoomType.custom ? room.name : room.roomType.label,
        images: images,
        idempotencyKey: key,
      );
    } on NetworkException {
      return _retryLater(job, JobError.network);
    } on UpstreamException {
      return _retryLater(job, JobError.upstream);
    } on QuotaExceededException {
      return _fail(job, JobError.quota);
    } on UnauthorizedException {
      return _fail(job, JobError.unauthorized);
    } on AppCheckFailedException {
      return _fail(job, JobError.appCheck);
    } on NoItemsRecognizedException {
      return _fail(job, JobError.noItems);
    } on PayloadTooLargeException {
      return _fail(job, JobError.tooLarge);
    } on ApiException catch (e) {
      return _fail(job, '${JobError.other}:${e.message}');
    }

    final now = _clock();
    final rows = [
      for (final item in response.items)
        _toCompanion(item, room.id, batch, response.promptVersion, now),
    ];

    await _db.transaction(() async {
      await _db.itemsDao.replaceAnalyzedItems(room.id, rows);
      await _db.capturesDao.markAnalyzed(batch.map((c) => c.id));
      await _db.roomsDao.setStatus(room.id, RoomStatus.analyzed);
      await jobs.updateJob(
        job.id,
        const AnalysisJobsCompanion(status: Value(AnalysisJobStatus.done)),
      );
    });
    return JobOutcome.done;
  }

  ItemsCompanion _toCompanion(
    AnalyzedItem item,
    String roomId,
    List<Capture> batch,
    String? promptVersion,
    DateTime now,
  ) {
    final idx = item.sourceImageIndex;
    final source = idx >= 0 && idx < batch.length ? batch[idx].id : null;
    return ItemsCompanion.insert(
      id: const Uuid().v4(),
      roomId: roomId,
      sourceCaptureId: Value(source),
      name: item.name,
      category: item.category,
      brand: Value(item.brand),
      model: Value(item.model),
      serial: Value(item.serial),
      qty: Value(item.qty < 1 ? 1 : item.qty),
      condition: Value(item.condition),
      estLow: Value(item.estLow),
      estHigh: Value(item.estHigh),
      currency: Value(item.currency),
      confidence: Value(item.confidence),
      isHighValue: Value(isHighValue(item.category, item.estHigh, highValueThreshold)),
      note: Value(item.note),
      promptVersion: Value(promptVersion),
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Spec §3.5: above the threshold, or a category that policies sub-limit.
  static bool isHighValue(ItemCategory category, double estHigh, double threshold) =>
      estHigh >= threshold || category.isSpecialCoverage;

  Future<JobOutcome> _retryLater(AnalysisJob job, String code) async {
    final attempts = job.attempts + 1;
    if (attempts >= JobError.maxTransientAttempts) return _fail(job, code);
    await _db.analysisJobsDao.updateJob(
      job.id,
      AnalysisJobsCompanion(
        status: const Value(AnalysisJobStatus.queued),
        lastError: Value(code),
      ),
    );
    return JobOutcome.retryLater;
  }

  Future<JobOutcome> _fail(AnalysisJob job, String code) async {
    await _db.analysisJobsDao.updateJob(
      job.id,
      AnalysisJobsCompanion(
        status: const Value(AnalysisJobStatus.failed),
        lastError: Value(code),
      ),
    );
    return JobOutcome.failed;
  }
}
