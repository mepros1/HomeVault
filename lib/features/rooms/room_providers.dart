import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../data/db/database.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../capture/capture_providers.dart';

// Written by hand rather than with riverpod_generator: see home_providers.dart.

final roomsForHomeProvider = StreamProvider.family<List<Room>, String>(
  (ref, homeId) => ref.watch(appDatabaseProvider).roomsDao.watchRoomsForHome(homeId),
);

final roomProvider = StreamProvider.family<Room?, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).roomsDao.watchRoom(roomId),
);

final captureCountProvider = StreamProvider.family<int, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).roomsDao.watchCaptureCount(roomId),
);

/// Thrown when a Free install tries to add a second room (spec §7).
class RoomLimitReached implements Exception {
  const RoomLimitReached(this.limit);

  final int limit;
}

class RoomRepository {
  RoomRepository(this._db, this._entitlement, {Future<void> Function()? afterDelete})
      : _afterDelete = afterDelete;

  final AppDatabase _db;
  final Entitlement Function() _entitlement;

  /// Storage sweep to run once the rows are gone (see StorageJanitor).
  final Future<void> Function()? _afterDelete;

  /// Adds a room at the end of the list. [name] is the display name; for
  /// presets pass the localized label, for custom rooms the user's text.
  Future<String> addRoom({
    required String homeId,
    required RoomType type,
    required String name,
  }) async {
    if (!_entitlement().isPro) {
      final count = await _db.roomsDao.countRoomsForHome(homeId);
      if (count >= Limits.freeTierRooms) {
        throw const RoomLimitReached(Limits.freeTierRooms);
      }
    }
    final id = const Uuid().v4();
    await _db.roomsDao.insertRoom(
      RoomsCompanion.insert(
        id: id,
        homeId: homeId,
        name: name.trim(),
        roomType: type,
        orderIndex: 0, // replaced by insertRoom
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  /// Moves the room at [fromIndex] to [toIndex] (final position, as given by
  /// ReorderableListView.onReorderItem).
  Future<void> reorder(List<Room> rooms, int fromIndex, int toIndex) {
    final ids = rooms.map((r) => r.id).toList();
    final moved = ids.removeAt(fromIndex);
    ids.insert(toIndex, moved);
    return _db.roomsDao.reorder(ids);
  }

  Future<void> rename(String roomId, String name) =>
      _db.roomsDao.renameRoom(roomId, name.trim());

  Future<void> delete(String roomId) async {
    await _db.roomsDao.deleteRoom(roomId);
    await _afterDelete?.call();
  }
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(currentEntitlementProvider),
    // Best effort: a failed sweep must never fail the delete itself.
    afterDelete: () => ref.read(storageJanitorProvider).sweep().then((_) {}, onError: (_) {}),
  ),
);
