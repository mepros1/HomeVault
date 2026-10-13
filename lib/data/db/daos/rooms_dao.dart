import 'package:drift/drift.dart';

import '../../../core/enums.dart';
import '../database.dart';
import '../tables.dart';

part 'rooms_dao.g.dart';

@DriftAccessor(tables: [Rooms, Captures])
class RoomsDao extends DatabaseAccessor<AppDatabase> with _$RoomsDaoMixin {
  RoomsDao(super.db);

  Stream<List<Room>> watchRoomsForHome(String homeId) => (select(rooms)
        ..where((r) => r.homeId.equals(homeId))
        ..orderBy([(r) => OrderingTerm.asc(r.orderIndex)]))
      .watch();

  Stream<Room?> watchRoom(String id) =>
      (select(rooms)..where((r) => r.id.equals(id))).watchSingleOrNull();

  Future<Room?> getRoom(String id) =>
      (select(rooms)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<int> countRoomsForHome(String homeId) async {
    final count = countAll();
    final q = selectOnly(rooms)
      ..addColumns([count])
      ..where(rooms.homeId.equals(homeId));
    return (await q.getSingle()).read(count) ?? 0;
  }

  /// Appends the room at the end of the home's list.
  Future<void> insertRoom(RoomsCompanion room) => transaction(() async {
        final homeId = room.homeId.value;
        final maxIndex = rooms.orderIndex.max();
        final q = selectOnly(rooms)
          ..addColumns([maxIndex])
          ..where(rooms.homeId.equals(homeId));
        final current = (await q.getSingle()).read(maxIndex);
        await into(rooms).insert(
          room.copyWith(orderIndex: Value(current == null ? 0 : current + 1)),
        );
      });

  Future<void> renameRoom(String roomId, String name) =>
      (update(rooms)..where((r) => r.id.equals(roomId)))
          .write(RoomsCompanion(name: Value(name)));

  Future<void> setStatus(String roomId, RoomStatus status) =>
      (update(rooms)..where((r) => r.id.equals(roomId)))
          .write(RoomsCompanion(status: Value(status)));

  /// Persists a drag-and-drop reorder: [orderedRoomIds] is the new full order.
  Future<void> reorder(List<String> orderedRoomIds) => transaction(() async {
        for (var i = 0; i < orderedRoomIds.length; i++) {
          await (update(rooms)..where((r) => r.id.equals(orderedRoomIds[i])))
              .write(RoomsCompanion(orderIndex: Value(i)));
        }
      });

  /// Cascades to captures, items and attachments (FK on delete cascade).
  Future<int> deleteRoom(String roomId) =>
      (delete(rooms)..where((r) => r.id.equals(roomId))).go();

  Future<List<Capture>> capturesForRoom(String roomId) => (select(captures)
        ..where((c) => c.roomId.equals(roomId))
        ..orderBy([(c) => OrderingTerm.asc(c.takenAt)]))
      .get();

  Stream<int> watchCaptureCount(String roomId) {
    final count = countAll();
    final q = selectOnly(captures)
      ..addColumns([count])
      ..where(captures.roomId.equals(roomId));
    return q.watchSingle().map((row) => row.read(count) ?? 0);
  }
}
