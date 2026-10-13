import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/api/api_errors.dart';
import 'package:homevault/data/auth/device_auth_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final endpoint = Uri.parse('http://example.test/v1/devices');

  test('posts device_id and platform, parses the token', () async {
    late http.Request seen;
    final client = DeviceAuthClient(
      endpoint: endpoint,
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'access_token': 'tok',
            'token_type': 'Bearer',
            'user_id': 'u-1',
          }),
          200,
        );
      }),
    );

    final result = await client.register(deviceId: 'd-1', deviceSecret: 'test-device-secret', platform: 'android');

    expect(seen.method, 'POST');
    expect(seen.url, endpoint);
    expect(seen.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {'device_id': 'd-1', 'device_secret': 'test-device-secret', 'platform': 'android'});
    expect(result.accessToken, 'tok');
    expect(result.userId, 'u-1');
  });

  test('non-200 becomes UnexpectedStatusException', () async {
    final client = DeviceAuthClient(
      endpoint: endpoint,
      httpClient: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(
      () => client.register(deviceId: 'd', deviceSecret: 'test-device-secret', platform: 'android'),
      throwsA(isA<UnexpectedStatusException>()),
    );
  });

  test('connection failure becomes NetworkException', () async {
    final client = DeviceAuthClient(
      endpoint: endpoint,
      httpClient: MockClient((_) => throw http.ClientException('offline')),
    );
    expect(
      () => client.register(deviceId: 'd', deviceSecret: 'test-device-secret', platform: 'android'),
      throwsA(isA<NetworkException>()),
    );
  });
}
