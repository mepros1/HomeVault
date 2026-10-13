import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/entitlement.dart';
import 'package:homevault/data/providers.dart';
import 'package:homevault/data/purchases/purchases_gateway.dart';
import 'package:homevault/data/settings/settings.dart';

void main() {
  group('CurrentEntitlement', () {
    test('follows store updates, purchases and restores', () async {
      final gateway = FakePurchasesGateway();
      final container = ProviderContainer(
        overrides: [purchasesGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      expect(container.read(currentEntitlementProvider), Entitlement.free);

      gateway.updates.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentEntitlementProvider), Entitlement.pro);

      gateway.updates.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentEntitlementProvider), Entitlement.free);

      final notifier = container.read(currentEntitlementProvider.notifier);
      expect(await notifier.buy(gateway.offer!), PurchaseOutcome.pro);
      expect(container.read(currentEntitlementProvider), Entitlement.pro);
      expect(gateway.buys, 1);

      gateway.restoreOutcome = PurchaseOutcome.notPro;
      expect(await notifier.restore(), PurchaseOutcome.notPro);
      expect(container.read(currentEntitlementProvider), Entitlement.free);
    });

    test('cancelled purchase leaves the plan untouched', () async {
      final gateway = FakePurchasesGateway(buyOutcome: PurchaseOutcome.cancelled);
      final container = ProviderContainer(
        overrides: [purchasesGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(currentEntitlementProvider.notifier);
      expect(await notifier.buy(gateway.offer!), PurchaseOutcome.cancelled);
      expect(container.read(currentEntitlementProvider), Entitlement.free);
    });

    test('no API key means an unavailable gateway', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(purchasesGatewayProvider), isA<UnavailablePurchasesGateway>());
      expect(container.read(purchasesGatewayProvider).isAvailable, isFalse);
    });
  });

  group('HighValueThreshold', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 21);
      await db.homesDao.insertHome(HomesCompanion.insert(
          id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
      await db.roomsDao.insertRoom(RoomsCompanion.insert(
          id: 'r', homeId: 'h', name: 'Room', roomType: RoomType.bedroom, orderIndex: 0, createdAt: now));
      ItemsCompanion item(String id, ItemCategory cat, double high) => ItemsCompanion.insert(
          id: id, roomId: 'r', name: id, category: cat, estHigh: Value(high),
          createdAt: now, updatedAt: now);
      await db.batch((b) => b.insertAll(db.items, [
            item('tv', ItemCategory.electronics, 900),
            item('sofa', ItemCategory.furniture, 2000),
            item('ring', ItemCategory.jewelryWatches, 200),
          ]));
    });

    tearDown(() => db.close());

    test('persists, loads and re-flags items', () async {
      final store = InMemorySettingsStore();
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      expect(container.read(highValueThresholdProvider), 1500);

      await container.read(highValueThresholdProvider.notifier).set(800);
      expect(container.read(highValueThresholdProvider), 800);
      expect(await store.readDouble(HighValueThreshold.key), 800);

      final flagged = {
        for (final i in await db.itemsDao.itemsForRoom('r')) i.id: i.isHighValue,
      };
      expect(flagged, {'tv': true, 'sofa': true, 'ring': true});

      await container.read(highValueThresholdProvider.notifier).set(5000);
      final flagged2 = {
        for (final i in await db.itemsDao.itemsForRoom('r')) i.id: i.isHighValue,
      };
      expect(flagged2, {'tv': false, 'sofa': false, 'ring': true},
          reason: 'jewelry stays flagged regardless of value');

      // A fresh container reads the stored value back.
      final container2 = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container2.dispose);
      container2.read(highValueThresholdProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container2.read(highValueThresholdProvider), 5000);
    });
  });
}
