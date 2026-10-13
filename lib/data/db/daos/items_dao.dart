import 'package:drift/drift.dart';

import '../../../core/enums.dart';
import '../database.dart';
import '../tables.dart';

part 'items_dao.g.dart';

@DriftAccessor(tables: [Items, Attachments])
class ItemsDao extends DatabaseAccessor<AppDatabase> with _$ItemsDaoMixin {
  ItemsDao(super.db);

  /// Review-screen order (spec §3.4): most expensive first.
  Stream<List<Item>> watchItemsForRoom(String roomId) => (select(items)
        ..where((i) => i.roomId.equals(roomId))
        ..orderBy([
          (i) => OrderingTerm.desc(i.estHigh),
          (i) => OrderingTerm.desc(i.confidence),
        ]))
      .watch();

  /// The card stack: unreviewed items in review order.
  Stream<List<Item>> watchPendingForRoom(String roomId) => (select(items)
        ..where((i) =>
            i.roomId.equals(roomId) & i.reviewStatus.equalsValue(ReviewStatus.pending))
        ..orderBy([
          (i) => OrderingTerm.desc(i.estHigh),
          (i) => OrderingTerm.desc(i.confidence),
        ]))
      .watch();

  Stream<Item?> watchItem(String id) =>
      (select(items)..where((i) => i.id.equals(id))).watchSingleOrNull();

  Future<Item?> getItem(String id) =>
      (select(items)..where((i) => i.id.equals(id))).getSingleOrNull();

  Future<List<Item>> itemsForRoom(String roomId) =>
      (select(items)..where((i) => i.roomId.equals(roomId))).get();

  Future<int> countForRoom(String roomId) => _count(items.roomId.equals(roomId));

  Future<int> countPendingForRoom(String roomId) => _count(
      items.roomId.equals(roomId) & items.reviewStatus.equalsValue(ReviewStatus.pending));

  /// Rows that a re-analysis would remove. Shown in the confirmation dialog
  /// before re-running analysis (spec §3.3).
  Future<int> countUnprotectedItems(String roomId) =>
      _count(items.roomId.equals(roomId) & _isUnprotected());

  Future<int> _count(Expression<bool> where) async {
    final count = countAll();
    final q = selectOnly(items)
      ..addColumns([count])
      ..where(where);
    return (await q.getSingle()).read(count) ?? 0;
  }

  /// Applies a fresh analysis result to a room.
  ///
  /// Rule (spec §3.3): rows with `user_edited = true` are never touched;
  /// everything else, accepted or not, is replaced by [fresh]. Keeping
  /// accepted rows was tried and produces duplicates, because a re-run
  /// recognises the same objects again.
  Future<void> replaceAnalyzedItems(
    String roomId,
    List<ItemsCompanion> fresh,
  ) =>
      transaction(() async {
        await (delete(items)
              ..where((i) => i.roomId.equals(roomId) & _isUnprotected()))
            .go();
        await batch((b) => b.insertAll(items, fresh));
      });

  Expression<bool> _isUnprotected() => items.userEdited.equals(false);

  Future<void> accept(String itemId) =>
      (update(items)..where((i) => i.id.equals(itemId))).write(
        ItemsCompanion(
          reviewStatus: const Value(ReviewStatus.accepted),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Any user change goes through here so `user_edited` is always set.
  Future<void> applyUserEdit(String itemId, ItemsCompanion changes) =>
      (update(items)..where((i) => i.id.equals(itemId))).write(
        changes.copyWith(
          userEdited: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<int> deleteItem(String itemId) =>
      (delete(items)..where((i) => i.id.equals(itemId))).go();

  /// Re-flags every item after the high-value threshold changes (spec §3.5):
  /// `est_high >= threshold` or a sub-limited category.
  Future<int> recomputeHighValue(double threshold) => customUpdate(
        'UPDATE items SET is_high_value = '
        '(COALESCE(est_high, 0) >= ? OR category IN (?, ?))',
        variables: [
          Variable.withReal(threshold),
          Variable.withString(ItemCategory.jewelryWatches.name),
          Variable.withString(ItemCategory.artCollectibles.name),
        ],
        updates: {items},
      );

  /// Puts a deleted row back verbatim (undo).
  Future<void> reinsert(Item item) => into(items).insert(item.toCompanion(false));

  Future<void> addAttachment(AttachmentsCompanion attachment) =>
      into(attachments).insert(attachment);

  Future<Attachment?> getAttachment(String id) =>
      (select(attachments)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<void> updateAttachment(String id, AttachmentsCompanion changes) =>
      (update(attachments)..where((a) => a.id.equals(id))).write(changes);

  Future<int> deleteAttachment(String id) =>
      (delete(attachments)..where((a) => a.id.equals(id))).go();

  Stream<List<Attachment>> watchAttachments(String itemId) => (select(attachments)
        ..where((a) => a.itemId.equals(itemId))
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
      .watch();
}
