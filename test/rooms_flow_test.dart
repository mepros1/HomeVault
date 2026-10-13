import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/entitlement.dart';
import 'package:homevault/data/providers.dart';
import 'package:homevault/features/home/home_screen.dart';
import 'package:homevault/features/rooms/room_providers.dart';
import 'package:homevault/features/rooms/room_screen.dart';
import 'package:homevault/l10n/app_localizations.dart';

/// Fails fast instead of waiting the default 10 minutes when something keeps animating.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

/// Unmounts the tree, then pumps once so Drift's zero-delay Timer.run (fired
/// when a stream loses its last listener) runs under fake async; otherwise
/// the test fails with "A Timer is still pending". The in-memory database is
/// deliberately left open: close() never completes under the widget test's
/// fake-async zone, and the database vanishes with the process anyway.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Drives the onboarding → rooms flow against an in-memory Drift database.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget app() {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/rooms/:roomId',
          builder: (_, state) => RoomScreen(roomId: state.pathParameters['roomId']!),
        ),
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

  testWidgets('create home, add a preset room, open it',
      timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Set up your home'), findsOneWidget);
    await tester.tap(find.text('Create home'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Our flat');
    await tester.tap(find.text('Create home'));
    await settle(tester);

    expect(find.text('Our flat'), findsOneWidget);
    expect(find.text('No rooms yet'), findsOneWidget);

    await tester.tap(find.text('Add room'));
    await settle(tester);
    await tester.tap(find.text('Kitchen'));
    await settle(tester);

    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('No photos'), findsOneWidget);
    expect(find.text('No photos yet'), findsOneWidget);

    await tester.tap(find.text('Kitchen'));
    await settle(tester);
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.textContaining('4 corners'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('free plan blocks the second room',
      timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Home');
    await tester.tap(find.text('Create home'));
    await settle(tester);

    // Both presets sit in the visible part of the sheet without scrolling.
    for (final room in ['Kitchen', 'Bathroom']) {
      await tester.tap(find.text('Add room'));
      await settle(tester);
      await tester.tap(find.text(room));
      await settle(tester);
    }

    expect(find.text('Free plan: one room'), findsOneWidget);
    expect(find.text('Bathroom'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Kitchen'), findsOneWidget);

    await finish(tester);
  });

  test('pro entitlement lifts the room limit; reorder and delete work', () async {
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(currentEntitlementProvider.notifier).set(Entitlement.pro);

    final now = DateTime.now();
    await db.homesDao.insertHome(HomesCompanion.insert(
      id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));

    final repo = container.read(roomRepositoryProvider);
    final a = await repo.addRoom(homeId: 'h', type: RoomType.kitchen, name: 'Kitchen');
    final b = await repo.addRoom(homeId: 'h', type: RoomType.garage, name: 'Garage');
    final c = await repo.addRoom(homeId: 'h', type: RoomType.custom, name: 'Loft');

    var rooms = await db.roomsDao.watchRoomsForHome('h').first;
    expect(rooms.map((r) => r.id), [a, b, c]);
    expect(rooms.map((r) => r.orderIndex), [0, 1, 2]);

    await repo.reorder(rooms, 2, 0); // Loft to the top
    rooms = await db.roomsDao.watchRoomsForHome('h').first;
    expect(rooms.map((r) => r.id), [c, a, b]);

    await repo.delete(a);
    rooms = await db.roomsDao.watchRoomsForHome('h').first;
    expect(rooms.map((r) => r.id), [c, b]);
  });
}
