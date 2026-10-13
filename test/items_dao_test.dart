import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 21);
    await db.into(db.homes).insert(
          HomesCompanion.insert(
            id: 'home',
            name: 'Test home',
            propertyType: PropertyType.house,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.roomsDao.insertRoom(
      RoomsCompanion.insert(
        id: 'room',
        homeId: 'home',
        name: 'Living Room',
        roomType: RoomType.livingRoom,
        orderIndex: 0,
        createdAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  ItemsCompanion item(String id, {bool edited = false, ReviewStatus? status}) {
    final now = DateTime.utc(2026, 9, 21);
    return ItemsCompanion.insert(
      id: id,
      roomId: 'room',
      name: 'Item $id',
      category: ItemCategory.other,
      userEdited: Value(edited),
      reviewStatus: status == null ? const Value.absent() : Value(status),
      createdAt: now,
      updatedAt: now,
    );
  }

  test('re-analysis keeps only user-edited items', () async {
    await db.batch(
      (b) => b.insertAll(db.items, [
        item('pending'),
        item('edited', edited: true),
        item('accepted', status: ReviewStatus.accepted),
      ]),
    );
    expect(await db.itemsDao.countUnprotectedItems('room'), 2);

    await db.itemsDao.replaceAnalyzedItems('room', [item('fresh')]);

    final ids = (await db.itemsDao.itemsForRoom('room')).map((i) => i.id);
    expect(ids, unorderedEquals(['edited', 'fresh']), reason: 'accepted rows are re-derivable and get replaced');
  });

  test('applyUserEdit always sets user_edited', () async {
    await db.into(db.items).insert(item('x'));
    await db.itemsDao.applyUserEdit(
      'x',
      const ItemsCompanion(brand: Value('Sony')),
    );
    final row = (await db.itemsDao.itemsForRoom('room')).single;
    expect(row.brand, 'Sony');
    expect(row.userEdited, isTrue);
  });

  test('deleting a room cascades to its items', () async {
    await db.into(db.items).insert(item('x'));
    await (db.delete(db.rooms)..where((r) => r.id.equals('room'))).go();
    expect(await db.itemsDao.itemsForRoom('room'), isEmpty);
  });
}
