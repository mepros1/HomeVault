// End-to-end flow on a device or emulator against an in-process fake server:
// onboarding -> room -> photos -> analysis -> review -> report.
//
//   flutter test integration_test/app_flow_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:9
//
// API_BASE_URL only has to be non-empty (it switches on the network paths in
// app.dart); every client is overridden to talk to the fake server below.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/app.dart';
import 'package:homevault/data/api/analyze_room_client.dart';
import 'package:homevault/data/auth/credential_store.dart';
import 'package:homevault/data/auth/device_auth_client.dart';
import 'package:homevault/data/auth/session.dart';
import 'package:homevault/data/backup/report_backup_client.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/entitlement.dart';
import 'package:homevault/data/providers.dart';
import 'package:homevault/data/purchases/purchases_gateway.dart';
import 'package:homevault/data/stats/review_stats_uploader.dart';
import 'package:homevault/features/capture/capture_providers.dart';
import 'package:homevault/features/report/report_providers.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Minimal HomeVault server: registration, one canned analysis, stats sink.
class FakeServer {
  FakeServer(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeServer> start() async =>
      FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  int registrations = 0;
  int analyses = 0;
  int statsUploads = 0;
  String? lastIdempotencyKey;

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    await req.fold<int>(0, (n, chunk) => n + chunk.length);
    final res = req.response;
    switch (req.uri.path) {
      case '/v1/devices':
        registrations++;
        _json(res, 200, {'access_token': 'it-token', 'token_type': 'Bearer', 'user_id': 'it-user'});
      case '/v1/analyze-room':
        analyses++;
        lastIdempotencyKey = req.headers.value('X-Idempotency-Key');
        _json(res, 200, {
          'request_id': 'req_it',
          'model': 'fake',
          'prompt_version': 'it-1',
          'items': [
            _item('Refrigerator', 'Appliances', 800, 1400, 0.92, 0),
            _item('Dining table', 'Furniture', 300, 700, 0.8, 1),
            _item('Kettle', 'Kitchenware', 20, 60, 0.45, 2),
          ],
          'usage': {'input_tokens': 10, 'output_tokens': 5},
          'warnings': <String>[],
        });
      case '/v1/stats/review':
        statsUploads++;
        res.statusCode = 204;
        await res.close();
      case '/v1/backups':
        _json(res, 200, {'backups': <Object>[], 'max_count': 20, 'max_total_bytes': 0});
      default:
        res.statusCode = 404;
        await res.close();
    }
  }

  static Map<String, Object?> _item(
      String name, String category, double low, double high, double confidence, int image) =>
      {
        'name': name,
        'category': category,
        'brand': null,
        'model': null,
        'serial': null,
        'qty': 1,
        'condition': 'good',
        'est_low': low,
        'est_high': high,
        'currency': 'USD',
        'confidence': confidence,
        'source_image_index': image,
        'note': null,
      };

  static void _json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }
}

Future<void> settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10));

/// Pumps until [finder] matches; integration tests run in real time.
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder');
}

Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for condition');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capturePortfolio = bool.fromEnvironment('PORTFOLIO_SCREENSHOTS');

  late FakeServer server;
  late AppDatabase db;
  late Directory base;
  late ProviderContainer container;

  setUp(() async {
    server = await FakeServer.start();
    db = AppDatabase(NativeDatabase.memory());
    base = await (await getTemporaryDirectory()).createTemp('it_');
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      captureBaseDirProvider.overrideWithValue(() async => base),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      purchasesGatewayProvider.overrideWithValue(FakePurchasesGateway()),
      deviceAuthClientProvider.overrideWithValue(DeviceAuthClient(endpoint: server.uri('/v1/devices'))),
      analyzeRoomClientProvider.overrideWith((ref) {
        final session = ref.watch(sessionProvider.notifier);
        return AnalyzeRoomClient(
          endpoint: server.uri('/v1/analyze-room'),
          accessToken: session.accessToken,
          refreshAccessToken: session.reissueToken,
        );
      }),
      reviewStatsUploaderProvider.overrideWith((ref) => ReviewStatsUploader(
            db,
            endpoint: server.uri('/v1/stats/review'),
            accessToken: ref.watch(sessionProvider.notifier).accessToken,
          )),
      reportBackupClientProvider.overrideWith((ref) {
        final session = ref.watch(sessionProvider.notifier);
        final client = ReportBackupClient(
          baseEndpoint: server.uri('/v1/backups'),
          accessToken: session.accessToken,
          refreshAccessToken: session.reissueToken,
        );
        ref.onDispose(client.close);
        return client;
      }),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await server.close();
    await base.delete(recursive: true);
  });

  testWidgets('onboarding, photos, analysis, review and report end to end', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const HomeVaultApp()));
    await settle(tester);
    if (capturePortfolio) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }

    // Onboarding.
    await tester.enterText(find.byType(TextFormField).first, 'Test flat');
    await tester.tap(find.text('Create home'));
    await settle(tester);
    await tester.tap(find.text('Add room'));
    await settle(tester);
    await tester.tap(find.text('Kitchen'));
    await settle(tester);
    await tester.tap(find.text('Kitchen'));
    await settle(tester);
    expect(find.text('Analyze room'), findsOneWidget);

    // Three "photos" straight into the capture store (the camera and the
    // system gallery picker cannot be driven from a test).
    final room = (await db.select(db.rooms).get()).single;
    final store = container.read(captureStoreProvider);
    for (final color in [
      img.ColorRgb8(200, 40, 40),
      img.ColorRgb8(40, 200, 40),
      img.ColorRgb8(40, 40, 200),
    ]) {
      final jpeg = img.encodeJpg(img.fill(img.Image(width: 640, height: 480), color: color), quality: 85);
      await store.addCapture(roomId: room.id, originalBytes: jpeg);
    }
    await pumpUntil(tester, find.text('3 photos'));

    // Analysis through the queue and the fake server.
    await tester.tap(find.text('Analyze room'));
    await pumpUntil(tester, find.text('Review items'));
    expect(server.registrations, greaterThanOrEqualTo(1));
    expect(server.analyses, 1);
    expect(server.lastIdempotencyKey, hasLength(64));
    expect(find.text('3 items recognised'), findsOneWidget);
    if (capturePortfolio) {
      await settle(tester);
      await binding.takeScreenshot('01_room_analysis');
    }

    // Review: most expensive first, the low-confidence kettle needs Confirm.
    await tester.tap(find.text('Review items'));
    await settle(tester);
    expect(find.text('Refrigerator'), findsOneWidget);
    if (capturePortfolio) await binding.takeScreenshot('02_item_review');
    for (var i = 0; i < 3; i++) {
      final accept = find.widgetWithText(FilledButton, 'Accept');
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      await tester.tap(accept.evaluate().isNotEmpty ? accept : confirm);
      await settle(tester);
    }
    expect(find.text('All items reviewed'), findsOneWidget);
    await waitFor(() => server.statsUploads >= 1);

    // Report screen and a real PDF on disk (Free tier: watermarked).
    await tester.pageBack();
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byTooltip('Report'));
    await settle(tester);
    expect(find.textContaining('3 items'), findsWidgets);

    final home = (await db.select(db.homes).get()).single;
    final report = await container.read(reportRepositoryProvider).generatePdf(home.id);
    final pdf = File(p.join(base.path, report.pdfPath));
    expect(await pdf.exists(), isTrue);
    expect(await pdf.length(), greaterThan(10 * 1024));
    expect(report.itemCount, 3);
    if (capturePortfolio) {
      await settle(tester);
      await binding.takeScreenshot('03_report_summary');
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['portfolio_pdf'] = base64Encode(await pdf.readAsBytes());
    }
  });
}
