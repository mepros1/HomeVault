import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/stats/review_stats_uploader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final endpoint = Uri.parse('http://server/v1/stats/review');

  test('sends only deltas since the last sync and re-bases on 204', () async {
    await db.reviewStatsDao.bump('v1', accepted: 3, edited: 1);
    await db.reviewStatsDao.bump('v2', deleted: 2);
    final bodies = <Map<String, dynamic>>[];
    final uploader = ReviewStatsUploader(
      db,
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer tok');
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );

    expect(await uploader.upload(), isTrue);
    expect(bodies.single['deltas'], [
      {'prompt_version': 'v1', 'accepted': 3, 'edited': 1, 'deleted': 0},
      {'prompt_version': 'v2', 'accepted': 0, 'edited': 0, 'deleted': 2},
    ]);

    // Nothing new: no request.
    expect(await uploader.upload(), isTrue);
    expect(bodies, hasLength(1));

    // Further reviews send only the difference.
    await db.reviewStatsDao.bump('v1', accepted: 2);
    expect(await uploader.upload(), isTrue);
    expect(bodies.last['deltas'], [
      {'prompt_version': 'v1', 'accepted': 2, 'edited': 0, 'deleted': 0},
    ]);
    expect(await db.reviewStatsDao.unsynced(), isEmpty);
  });

  test('keeps counters unsynced on failure and re-issues the token once on 401', () async {
    await db.reviewStatsDao.bump('v1', accepted: 1);
    var calls = 0;
    final uploader = ReviewStatsUploader(
      db,
      endpoint: endpoint,
      accessToken: () => 'stale',
      refreshAccessToken: () => 'fresh',
      httpClient: MockClient((req) async {
        calls++;
        return http.Response('', req.headers['Authorization'] == 'Bearer fresh' ? 204 : 401);
      }),
    );
    expect(await uploader.upload(), isTrue);
    expect(calls, 2);

    await db.reviewStatsDao.bump('v1', deleted: 1);
    final failing = ReviewStatsUploader(
      db,
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((_) async => http.Response('', 503)),
    );
    expect(await failing.upload(), isFalse);
    expect(await db.reviewStatsDao.unsynced(), hasLength(1));
  });

  test('a negative delta after undo is reported as zero and re-based', () async {
    await db.reviewStatsDao.bump('v1', deleted: 1);
    final uploader = ReviewStatsUploader(
      db,
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    await uploader.upload();
    await db.reviewStatsDao.bump('v1', deleted: -1);
    final bodies = <String>[];
    final second = ReviewStatsUploader(
      db,
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 204);
      }),
    );
    expect(await second.upload(), isTrue);
    expect(bodies.single, contains('"deleted":0'));
    expect(await db.reviewStatsDao.unsynced(), isEmpty);
  });
}
