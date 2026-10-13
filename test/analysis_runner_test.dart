import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/analysis/analysis_queue.dart';
import 'package:homevault/data/analysis/analysis_runner.dart';
import 'package:homevault/data/api/analyze_room_client.dart';
import 'package:homevault/data/api/idempotency.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/media/capture_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

void main() {
  late AppDatabase db;
  late Directory base;
  late CaptureStore store;
  late List<http.BaseRequest> requests;
  late Future<http.Response> Function(http.BaseRequest) handler;

  final Uint8List jpeg = img.encodeJpg(
    img.fill(img.Image(width: 640, height: 480), color: img.ColorRgb8(20, 120, 200)),
    quality: 80,
  );

  String okBody({List<Map<String, Object?>>? items}) => jsonEncode({
        'request_id': 'req_1',
        'model': 'gemini-test',
        'prompt_version': 'v-test',
        'items': items ??
            [
              {
                'name': 'Television',
                'category': 'Electronics',
                'brand': 'Samsung',
                'qty': 1,
                'condition': 'good',
                'est_low': 400,
                'est_high': 900,
                'currency': 'USD',
                'confidence': 0.86,
                'source_image_index': 1,
                'note': '55 inch',
              },
              {
                'name': 'Gold necklace',
                'category': 'Jewelry & Watches',
                'qty': 1,
                'est_low': 200,
                'est_high': 500,
                'currency': 'USD',
                'confidence': 0.5,
                'source_image_index': 0,
              },
              {
                'name': 'Piano',
                'category': 'Musical Instruments',
                'qty': 1,
                'est_low': 3000,
                'est_high': 6000,
                'currency': 'USD',
                'confidence': 0.9,
                'source_image_index': 7,
              },
            ],
        'usage': {'input_tokens': 10, 'output_tokens': 20},
        'warnings': [],
      });

  AnalysisRunner runner() => AnalysisRunner(
        db: db,
        captures: store,
        client: AnalyzeRoomClient(
          endpoint: Uri.parse('http://example.test/v1/analyze-room'),
          accessToken: () => 'tok',
          httpClient: MockClient((req) {
            requests.add(req);
            return handler(req);
          }),
        ),
        clock: () => DateTime.utc(2026, 9, 21, 12),
      );

  Future<AnalysisJob> job() async {
    final now = DateTime.now();
    await db.analysisJobsDao.insertJob(AnalysisJobsCompanion.insert(
        id: 'job', roomId: 'r', idempotencyKey: '', createdAt: now, updatedAt: now));
    return (await db.analysisJobsDao.getJob('job'))!;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_analysis_');
    store = CaptureStore(db, baseDir: () async => base);
    requests = [];
    handler = (_) async => http.Response(okBody(), 200);

    final now = DateTime.utc(2026, 9, 21);
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'r', homeId: 'h', name: 'Kitchen', roomType: RoomType.kitchen, orderIndex: 0, createdAt: now));
    for (var i = 0; i < 3; i++) {
      await store.addCapture(roomId: 'r', originalBytes: jpeg, takenAt: now.add(Duration(minutes: i)));
    }
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  test('success: uploads captures, writes items, flags high value, marks room analyzed', () async {
    final outcome = await runner().run(await job());
    expect(outcome, JobOutcome.done);

    // MockClient hands the handler a flattened Request; inspect the raw body.
    final req = requests.single as http.Request;
    final body = latin1.decode(req.bodyBytes);
    expect(body, contains('name="room_type"\r\n\r\nKitchen'));
    expect('filename="img_'.allMatches(body), hasLength(3));
    final captures = await db.capturesDao.forRoom('r');
    expect(req.headers['X-Idempotency-Key'], idempotencyKeyFor(captures.map((c) => c.sha256)));
    expect(captures.every((c) => c.analyzed), isTrue);

    final items = await db.itemsDao.itemsForRoom('r');
    expect(items, hasLength(3));
    final tv = items.firstWhere((i) => i.name == 'Television');
    expect(tv.sourceCaptureId, captures[1].id);
    expect(tv.isHighValue, isFalse);
    expect(tv.promptVersion, 'v-test');
    expect(tv.condition, ItemCondition.good);
    expect(tv.reviewStatus, ReviewStatus.pending);
    expect(tv.userEdited, isFalse);

    final necklace = items.firstWhere((i) => i.name == 'Gold necklace');
    expect(necklace.isHighValue, isTrue, reason: 'jewelry is always flagged');
    final piano = items.firstWhere((i) => i.name == 'Piano');
    expect(piano.isHighValue, isTrue, reason: 'above the 1500 threshold');
    expect(piano.sourceCaptureId, isNull, reason: 'index 7 is out of range');

    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.analyzed);
    final done = (await db.analysisJobsDao.getJob('job'))!;
    expect(done.status, AnalysisJobStatus.done);
    expect(done.attempts, 1);
  });

  test('re-analysis keeps edited items, replaces accepted and pending ones', () async {
    await runner().run(await job());
    final before = await db.itemsDao.itemsForRoom('r');
    final tv = before.firstWhere((i) => i.name == 'Television');
    final piano = before.firstWhere((i) => i.name == 'Piano');
    await db.itemsDao.applyUserEdit(tv.id, const ItemsCompanion(brand: Value('LG')));
    await db.itemsDao.accept(piano.id);

    handler = (_) async => http.Response(okBody(items: [
          {
            'name': 'Blender',
            'category': 'Appliances',
            'qty': 1,
            'est_low': 50,
            'est_high': 120,
            'currency': 'USD',
            'confidence': 0.8,
            'source_image_index': 0,
          }
        ]), 200);
    final now = DateTime.now();
    await db.analysisJobsDao.insertJob(AnalysisJobsCompanion.insert(
        id: 'job2', roomId: 'r', idempotencyKey: '', createdAt: now, updatedAt: now));
    await runner().run((await db.analysisJobsDao.getJob('job2'))!);

    final after = (await db.itemsDao.itemsForRoom('r')).map((i) => i.name).toList();
    expect(after, unorderedEquals(['Television', 'Blender']));
  });

  test('offline: job stays queued with a network error code', () async {
    handler = (_) => throw http.ClientException('offline');
    final outcome = await runner().run(await job());
    expect(outcome, JobOutcome.retryLater);
    final j = (await db.analysisJobsDao.getJob('job'))!;
    expect(j.status, AnalysisJobStatus.queued);
    expect(j.lastError, JobError.network);
    expect(j.attempts, 1);
    expect(await db.itemsDao.itemsForRoom('r'), isEmpty);
    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.captured);
  });

  test('quota exhausted: job fails with the quota code', () async {
    handler = (_) async => http.Response(
        jsonEncode({'error': 'quota_exceeded', 'limit': 3, 'used': 3, 'resets_at': '2026-10-01T00:00:00Z'}),
        429);
    expect(await runner().run(await job()), JobOutcome.failed);
    expect((await db.analysisJobsDao.getJob('job'))!.lastError, JobError.quota);
  });

  test('network rate limit leaves the job queued for a later retry', () async {
    handler = (_) async => http.Response('{"error":"rate_limited","message":"Too many requests"}', 429);
    expect(await runner().run(await job()), JobOutcome.retryLater);
    final saved = (await db.analysisJobsDao.getJob('job'))!;
    expect(saved.status, AnalysisJobStatus.queued);
    expect(saved.lastError, JobError.upstream);
  });

  test('too few photos fails without calling the server', () async {
    final captures = await db.capturesDao.forRoom('r');
    await store.deleteCapture(captures.first.id);
    expect(await runner().run(await job()), JobOutcome.failed);
    expect((await db.analysisJobsDao.getJob('job'))!.lastError, JobError.notEnoughPhotos);
    expect(requests, isEmpty);
  });

  test('queue: enqueue is idempotent per room, drain runs jobs in order, retry re-queues', () async {
    final queue = AnalysisQueue(db, runner());
    handler = (_) => throw http.ClientException('offline');

    final id1 = await queue.enqueue('r');
    await queue.drain();
    expect(await queue.enqueue('r'), id1, reason: 'still queued -> same job');
    expect((await db.analysisJobsDao.getJob(id1))!.status, AnalysisJobStatus.queued);

    handler = (_) async => http.Response(okBody(), 200);
    await queue.drain();
    expect((await db.analysisJobsDao.getJob(id1))!.status, AnalysisJobStatus.done);
    expect(await db.itemsDao.itemsForRoom('r'), hasLength(3));

    handler = (_) async => http.Response('', 422);
    final id2 = await queue.enqueue('r');
    await queue.drain();
    expect(id2, isNot(id1));
    expect((await db.analysisJobsDao.getJob(id2))!.status, AnalysisJobStatus.failed);

    handler = (_) async => http.Response(okBody(), 200);
    await queue.retry(id2);
    expect((await db.analysisJobsDao.getJob(id2))!.status, AnalysisJobStatus.done);
  });

  test('start() recovers a job stuck in running', () async {
    final now = DateTime.now();
    await db.analysisJobsDao.insertJob(AnalysisJobsCompanion.insert(
        id: 'stuck', roomId: 'r', idempotencyKey: '', status: const Value(AnalysisJobStatus.running),
        createdAt: now, updatedAt: now));
    final queue = AnalysisQueue(db, runner());
    await queue.start();
    await queue.drain();
    expect((await db.analysisJobsDao.getJob('stuck'))!.status, AnalysisJobStatus.done);
  });
}
