import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/providers.dart';
import 'package:homevault/features/items/item_screen.dart';
import 'package:homevault/features/review/review_screen.dart';
import 'package:homevault/l10n/app_localizations.dart';

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

/// See CLAUDE.md "Testing notes": unmount, then let Drift's zero-delay timer fire.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;

  Future<void> seed({bool withLowConfidence = true}) async {
    final now = DateTime.utc(2026, 9, 21);
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'r', homeId: 'h', name: 'Living Room', roomType: RoomType.livingRoom,
        orderIndex: 0, status: const Value(RoomStatus.analyzed), createdAt: now));
    ItemsCompanion item(String id, String name, double high, double confidence,
            {ItemCategory category = ItemCategory.furniture}) =>
        ItemsCompanion.insert(
          id: id, roomId: 'r', name: name, category: category,
          estLow: Value(high / 2), estHigh: Value(high), confidence: Value(confidence),
          promptVersion: const Value('v1'), createdAt: now, updatedAt: now,
        );
    await db.batch((b) => b.insertAll(db.items, [
          item('sofa', 'Sofa', 900, 0.9),
          item('tv', 'Television', 1200, 0.85, category: ItemCategory.electronics),
          if (withLowConfidence) item('vase', 'Vase', 40, 0.4, category: ItemCategory.homeDecor),
        ]));
  }

  Widget app({String initial = '/rooms/r/review'}) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('room'))),
        GoRoute(path: '/rooms/:roomId/review',
            builder: (_, s) => ReviewScreen(roomId: s.pathParameters['roomId']!)),
        GoRoute(path: '/items/:itemId',
            builder: (_, s) => ItemScreen(itemId: s.pathParameters['itemId']!)),
      ],
    );
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seed();
  });

  testWidgets('most expensive first; accept, delete with undo, confirm low confidence; room becomes reviewed',
      timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    // Top card is the TV (est_high 1200), Sofa peeks underneath.
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('0 of 3 reviewed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await settle(tester);
    expect(find.text('1 of 3 reviewed'), findsOneWidget);
    expect((await db.itemsDao.getItem('tv'))!.reviewStatus, ReviewStatus.accepted);

    // Sofa: delete, then undo from the snackbar.
    expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await settle(tester);
    expect(await db.itemsDao.getItem('sofa'), isNull);
    expect(find.text('Deleted Sofa'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await db.itemsDao.getItem('sofa'), isNotNull);
    expect(find.text('1 of 3 reviewed'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await settle(tester);

    // Vase has confidence 0.4: swipe-accept is refused, the button says Confirm.
    expect(find.text('Vase'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    await tester.drag(find.byType(Dismissible), const Offset(600, 0));
    await settle(tester);
    expect(find.text('Vase'), findsOneWidget, reason: 'low-confidence swipe must not accept');
    expect((await db.itemsDao.getItem('vase'))!.reviewStatus, ReviewStatus.pending);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);
    expect(find.text('All items reviewed'), findsOneWidget);
    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.reviewed);

    final stats = await db.reviewStatsDao.all();
    expect(stats.single.promptVersion, 'v1');
    expect(stats.single.accepted, 3);
    expect(stats.single.deleted, 0, reason: 'undo reverses the counter');

    await finish(tester);
  });

  testWidgets('swipe right accepts a confident item', timeout: const Timeout(Duration(seconds: 90)),
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.drag(find.byType(Dismissible), const Offset(600, 0));
    await settle(tester);
    expect((await db.itemsDao.getItem('tv'))!.reviewStatus, ReviewStatus.accepted);
    expect(find.text('Sofa'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('editing on the item card sets user_edited, accepts and recomputes high value',
      timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    await tester.pumpWidget(app(initial: '/items/sofa'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Brand'), 'IKEA');
    await tester.enterText(find.widgetWithText(TextFormField, 'Estimate to'), '2000');
    await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final sofa = (await db.itemsDao.getItem('sofa'))!;
    expect(sofa.brand, 'IKEA');
    expect(sofa.estHigh, 2000);
    expect(sofa.userEdited, isTrue);
    expect(sofa.reviewStatus, ReviewStatus.accepted);
    expect(sofa.isHighValue, isTrue);
    final stats = await db.reviewStatsDao.all();
    expect(stats.single.edited, 1);
    expect(stats.single.accepted, 1);

    await finish(tester);
  });

  testWidgets('item card rejects a high estimate below the low one',
      timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    await tester.pumpWidget(app(initial: '/items/sofa'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Estimate to'), '100');
    await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Must be at least the low estimate'), findsOneWidget);
    expect((await db.itemsDao.getItem('sofa'))!.userEdited, isFalse);
    await finish(tester);
  });
}
