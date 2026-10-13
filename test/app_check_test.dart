import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/api/analyze_room_client.dart';
import 'package:homevault/data/auth/device_auth_client.dart';
import 'package:homevault/data/integrity/app_check.dart';
import 'package:homevault/data/media/image_prep.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const okAnalyze = '''
  {"request_id":"req_1","model":"m","prompt_version":"v","items":[],
   "usage":{"input_tokens":1,"output_tokens":2},"warnings":[]}''';

  test('registration binds the token to the device id and sends the header', () async {
    final appCheck = FakeAppCheck(nextToken: 'integrity-1');
    late http.Request seen;
    final client = DeviceAuthClient(
      endpoint: Uri.parse('http://example.test/v1/devices'),
      appCheck: appCheck,
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({'access_token': 't', 'token_type': 'Bearer', 'user_id': 'u'}),
          200,
        );
      }),
    );

    await client.register(deviceId: 'dev-42', deviceSecret: 'test-device-secret', platform: 'android');

    expect(appCheck.requestedHashes, ['dev-42']);
    expect(seen.headers['X-App-Check'], 'integrity-1');
  });

  test('analysis binds the token to the idempotency key; no token, no header', () async {
    final images = [
      PreparedImage(bytes: Uint8List.fromList([1, 2, 3]), width: 1, height: 1, quality: 80),
    ];
    final appCheck = FakeAppCheck(nextToken: 'integrity-2');
    final headers = <String?>[];
    AnalyzeRoomClient build() => AnalyzeRoomClient(
          endpoint: Uri.parse('http://example.test/v1/analyze-room'),
          accessToken: () => 'tok',
          appCheck: appCheck,
          httpClient: MockClient((req) async {
            headers.add(req.headers['X-App-Check']);
            return http.Response(okAnalyze, 200);
          }),
        );

    await build().analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'key-1');
    expect(appCheck.requestedHashes, ['key-1']);
    expect(headers, ['integrity-2']);

    appCheck.nextToken = null;
    await build().analyzeRoom(roomType: 'Kitchen', images: images, idempotencyKey: 'key-2');
    expect(headers.last, isNull);
  });

  test('PlayIntegrityAppCheck prepares once and degrades to null on failure', () async {
    const channel = MethodChannel('homevault/app_check');
    final calls = <MethodCall>[];
    var failToken = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'prepare':
            return true;
          case 'token':
            if (failToken) throw PlatformException(code: 'request_failed');
            return 'tok-for-${(call.arguments as Map)['requestHash']}';
        }
        return null;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final check = PlayIntegrityAppCheck(cloudProjectNumber: 123456, channel: channel);
    await check.prepare();
    expect(await check.token('h1'), 'tok-for-h1');
    expect(calls.where((c) => c.method == 'prepare'), hasLength(1));
    expect((calls.first.arguments as Map)['cloudProjectNumber'], 123456);

    failToken = true;
    expect(await check.token('h2'), isNull);
  });
}
