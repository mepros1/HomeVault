import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/api/analyze_room_client.dart';
import 'package:homevault/data/api/api_errors.dart';
import 'package:homevault/data/media/image_prep.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final endpoint = Uri.parse('http://example.test/v1/analyze-room');
  final images = [
    PreparedImage(bytes: Uint8List.fromList([1, 2, 3]), width: 1, height: 1, quality: 80),
  ];

  const okBody = '''
  {"request_id":"req_1","model":"m","prompt_version":"v","items":[],
   "usage":{"input_tokens":1,"output_tokens":2},"warnings":[]}''';

  test('sends bearer token, idempotency key and multipart fields', () async {
    late http.BaseRequest seen;
    final client = AnalyzeRoomClient(
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(okBody, 200);
      }),
    );

    final res = await client.analyzeRoom(
      roomType: 'Living Room',
      images: images,
      idempotencyKey: 'k1',
    );

    expect(res.requestId, 'req_1');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.headers['X-Idempotency-Key'], 'k1');
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
  });

  test('401 re-issues the token once and retries with it', () async {
    final authHeaders = <String>[];
    final client = AnalyzeRoomClient(
      endpoint: endpoint,
      accessToken: () => 'stale',
      refreshAccessToken: () => 'fresh',
      httpClient: MockClient((req) async {
        authHeaders.add(req.headers['Authorization']!);
        return req.headers['Authorization'] == 'Bearer fresh'
            ? http.Response(okBody, 200)
            : http.Response('', 401);
      }),
    );

    await client.analyzeRoom(
      roomType: 'Kitchen',
      images: images,
      idempotencyKey: 'k',
    );

    expect(authHeaders, ['Bearer stale', 'Bearer fresh']);
  });

  test('401 after a re-issue surfaces UnauthorizedException', () async {
    final client = AnalyzeRoomClient(
      endpoint: endpoint,
      accessToken: () => 'a',
      refreshAccessToken: () => 'b',
      httpClient: MockClient((_) async => http.Response('', 401)),
    );
    expect(
      () => client.analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'k'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('429 carries limit and resets_at from the body', () async {
    final client = AnalyzeRoomClient(
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'quota_exceeded',
            'limit': 3,
            'used': 3,
            'resets_at': '2026-10-01T00:00:00Z',
          }),
          429,
        ),
      ),
    );
    expect(
      () => client.analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'k'),
      throwsA(
        isA<QuotaExceededException>()
            .having((e) => e.limit, 'limit', 3)
            .having((e) => e.resetsAt.toUtc(), 'resetsAt', DateTime.utc(2026, 10, 1)),
      ),
    );
  });

  test('network rate limit does not parse a missing monthly quota', () async {
    final client = AnalyzeRoomClient(
      endpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((_) async => http.Response(
        '{"error":"rate_limited","message":"Too many requests"}', 429)),
    );
    expect(
      () => client.analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'k'),
      throwsA(isA<UpstreamException>().having((e) => e.statusCode, 'status', 429)),
    );
  });

  test('413 and 422 map to their exceptions', () async {
    for (final (status, matcher) in [
      (413, isA<PayloadTooLargeException>()),
      (422, isA<NoItemsRecognizedException>()),
    ]) {
      final client = AnalyzeRoomClient(
        endpoint: endpoint,
        accessToken: () => 'tok',
        httpClient: MockClient((_) async => http.Response('', status)),
      );
      await expectLater(
        client.analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'k'),
        throwsA(matcher),
      );
    }
  });
}
