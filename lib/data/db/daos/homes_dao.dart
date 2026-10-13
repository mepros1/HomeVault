import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'homes_dao.g.dart';

@DriftAccessor(tables: [Homes])
class HomesDao extends DatabaseAccessor<AppDatabase> with _$HomesDaoMixin {
  HomesDao(super.db);

  /// v1 supports a single home; the oldest row is "the" home.
  Stream<Home?> watchCurrentHome() => (select(homes)
        ..orderBy([(h) => OrderingTerm.asc(h.createdAt)])
        ..limit(1))
      .watchSingleOrNull();

  Future<void> insertHome(HomesCompanion home) => into(homes).insert(home);

  Future<void> updateHome(String id, HomesCompanion changes) =>
      (update(homes)..where((h) => h.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(DateTime.now())),
      );
}
