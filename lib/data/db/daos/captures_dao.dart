import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'captures_dao.g.dart';

@DriftAccessor(tables: [Captures])
class CapturesDao extends DatabaseAccessor<AppDatabase> with _$CapturesDaoMixin {
  CapturesDao(super.db);

  Stream<List<Capture>> watchForRoom(String roomId) => (select(captures)
        ..where((c) => c.roomId.equals(roomId))
        ..orderBy([(c) => OrderingTerm.asc(c.takenAt)]))
      .watch();

  Future<List<Capture>> forRoom(String roomId) => (select(captures)
        ..where((c) => c.roomId.equals(roomId))
        ..orderBy([(c) => OrderingTerm.asc(c.takenAt)]))
      .get();

  Future<Capture?> getCapture(String id) =>
      (select(captures)..where((c) => c.id.equals(id))).getSingleOrNull();

  Stream<Capture?> watchCapture(String id) =>
      (select(captures)..where((c) => c.id.equals(id))).watchSingleOrNull();

  Future<int> countForRoom(String roomId) async {
    final count = countAll();
    final q = selectOnly(captures)
      ..addColumns([count])
      ..where(captures.roomId.equals(roomId));
    return (await q.getSingle()).read(count) ?? 0;
  }

  Future<void> insertCapture(CapturesCompanion capture) =>
      into(captures).insert(capture);

  Future<void> markAnalyzed(Iterable<String> ids) =>
      (update(captures)..where((c) => c.id.isIn(ids)))
          .write(const CapturesCompanion(analyzed: Value(true)));

  Future<int> deleteCapture(String id) =>
      (delete(captures)..where((c) => c.id.equals(id))).go();
}
