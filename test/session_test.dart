import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/api/api_errors.dart';
import 'package:homevault/data/auth/credential_store.dart';
import 'package:homevault/data/auth/device_auth_client.dart';
import 'package:homevault/data/auth/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late InMemoryCredentialStore store;
  late List<String> registeredDeviceIds;
  late List<String> registeredSecrets;
  var nextToken = 0;
  var failRegistration = false;

  DeviceAuthClient fakeAuth() => DeviceAuthClient(
        endpoint: Uri.parse('http://example.test/v1/devices'),
        httpClient: MockClient((req) async {
          if (failRegistration) return http.Response('down', 503);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          registeredDeviceIds.add(body['device_id'] as String);
          registeredSecrets.add(body['device_secret'] as String);
          nextToken++;
          return http.Response(
            jsonEncode({
              'access_token': 'tok-$nextToken',
              'token_type': 'Bearer',
              'user_id': 'user-for-${body['device_id']}',
            }),
            200,
          );
        }),
      );

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        credentialStoreProvider.overrideWithValue(store),
        deviceAuthClientProvider.overrideWithValue(fakeAuth()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    store = InMemoryCredentialStore();
    registeredDeviceIds = [];
    registeredSecrets = [];
    nextToken = 0;
    failRegistration = false;
  });

  test('first launch: generates a device id, registers, stores the token', () async {
    final c = container();
    final session = c.read(sessionProvider.notifier);

    final token = await session.accessToken();

    expect(token, 'tok-1');
    expect(registeredDeviceIds, hasLength(1));
    final stored = await store.read();
    expect(stored!.deviceId, registeredDeviceIds.single);
    expect(stored.accessToken, 'tok-1');
    expect(stored.deviceSecret, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(registeredSecrets.single, stored.deviceSecret);
    expect(c.read(sessionProvider).status, SessionStatus.ready);
    expect(c.read(sessionProvider).userId, 'user-for-${stored.deviceId}');
  });

  test('later launch reuses the stored token without a network call', () async {
    await store.write(const StoredCredentials(
      deviceId: 'existing', accessToken: 'stored-tok', userId: 'u'));
    final c = container();

    final token = await c.read(sessionProvider.notifier).accessToken();

    expect(token, 'stored-tok');
    expect(registeredDeviceIds, isEmpty);
  });

  test('reissueToken registers the same device id again', () async {
    await store.write(const StoredCredentials(
      deviceId: 'existing', deviceSecret: 'original-secret', accessToken: 'old', userId: 'u'));
    final c = container();
    final session = c.read(sessionProvider.notifier);
    await session.accessToken();

    final fresh = await session.reissueToken();

    expect(fresh, 'tok-1');
    expect(registeredDeviceIds, ['existing']);
    expect(registeredSecrets, ['original-secret']);
    expect((await store.read())!.accessToken, 'tok-1');
  });

  test('concurrent callers share one registration', () async {
    final c = container();
    final session = c.read(sessionProvider.notifier);

    final tokens = await Future.wait([session.accessToken(), session.accessToken()]);

    expect(tokens, ['tok-1', 'tok-1']);
    expect(registeredDeviceIds, hasLength(1));
  });

  test('failed registration keeps the device id for the next attempt', () async {
    failRegistration = true;
    final c = container();
    final session = c.read(sessionProvider.notifier);

    await expectLater(session.accessToken(), throwsA(isA<UnexpectedStatusException>()));
    expect(c.read(sessionProvider).status, SessionStatus.failed);
    final afterFailure = await store.read();
    expect(afterFailure!.hasToken, isFalse);

    failRegistration = false;
    final token = await session.accessToken();
    expect(token, 'tok-1');
    expect(registeredDeviceIds, [afterFailure.deviceId]);
  });

  test('device identity and registration share one persisted secret', () async {
    final c = container();
    final session = c.read(sessionProvider.notifier);
    final results = await Future.wait<String>([session.deviceId(), session.accessToken()]);
    final saved = (await store.read())!;
    expect(results.first, saved.deviceId);
    expect(registeredDeviceIds, [saved.deviceId]);
    expect(registeredSecrets, [saved.deviceSecret]);
    expect(await session.deviceId(), saved.deviceId);
  });

  test('deviceId is created without registering and is reused by it', () async {
    final c = container();
    final session = c.read(sessionProvider.notifier);

    final id = await session.deviceId();

    expect(id, isNotEmpty);
    expect(registeredDeviceIds, isEmpty);
    expect((await store.read())!.deviceId, id);
    expect(await session.deviceId(), id);

    await session.accessToken();
    expect(registeredDeviceIds, [id]);
  });
}
