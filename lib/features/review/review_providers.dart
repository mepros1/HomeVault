import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums.dart';
import '../../core/env.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

// Hand-written providers: they carry Drift row classes (see CLAUDE.md).

final pendingItemsForRoomProvider = StreamProvider.family<List<Item>, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).itemsDao.watchPendingForRoom(roomId),
);

final itemProvider = StreamProvider.family<Item?, String>(
  (ref, itemId) => ref.watch(appDatabaseProvider).itemsDao.watchItem(itemId),
);

final captureByIdProvider = StreamProvider.family<Capture?, String>(
  (ref, captureId) => ref.watch(appDatabaseProvider).capturesDao.watchCapture(captureId),
);

/// Review actions (spec §3.4) plus the quality counters (spec §10) and the
/// room's `reviewed` transition.
class ReviewRepository {
  ReviewRepository(this._db, {Future<void> Function()? afterReviewed})
      : _afterReviewed = afterReviewed;

  final AppDatabase _db;
  final Future<void> Function()? _afterReviewed;

  Future<void> accept(Item item) async {
    await _db.itemsDao.accept(item.id);
    await _db.reviewStatsDao.bump(item.promptVersion, accepted: 1);
    await _refreshRoomStatus(item.roomId);
  }

  Future<void> delete(Item item) async {
    await _db.itemsDao.deleteItem(item.id);
    await _db.reviewStatsDao.bump(item.promptVersion, deleted: 1);
    await _refreshRoomStatus(item.roomId);
  }

  Future<void> undoDelete(Item item) async {
    await _db.itemsDao.reinsert(item);
    await _db.reviewStatsDao.bump(item.promptVersion, deleted: -1);
    await _refreshRoomStatus(item.roomId);
  }

  /// Saving the detail card counts as reviewing the item, so it is accepted.
  Future<void> saveEdits(Item item, ItemsCompanion changes) async {
    await _db.itemsDao.applyUserEdit(
      item.id,
      changes.copyWith(reviewStatus: const Value(ReviewStatus.accepted)),
    );
    await _db.reviewStatsDao.bump(
      item.promptVersion,
      edited: item.userEdited ? 0 : 1,
      accepted: item.reviewStatus == ReviewStatus.accepted ? 0 : 1,
    );
    await _refreshRoomStatus(item.roomId);
  }

  /// analyzed ⇄ reviewed depending on whether anything is still pending.
  Future<void> _refreshRoomStatus(String roomId) async {
    final room = await _db.roomsDao.getRoom(roomId);
    if (room == null) return;
    if (room.status != RoomStatus.analyzed && room.status != RoomStatus.reviewed) return;
    final total = await _db.itemsDao.countForRoom(roomId);
    final pending = await _db.itemsDao.countPendingForRoom(roomId);
    final target = total > 0 && pending == 0 ? RoomStatus.reviewed : RoomStatus.analyzed;
    if (room.status != target) {
      await _db.roomsDao.setStatus(roomId, target);
      if (target == RoomStatus.reviewed) await _afterReviewed?.call();
    }
  }
}

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(
    ref.watch(appDatabaseProvider),
    // A finished room is a natural moment to report the quality counters.
    afterReviewed: Env.isApiConfigured
        ? () => ref.read(reviewStatsUploaderProvider).upload().then((_) {}, onError: (_) {})
        : null,
  ),
);
