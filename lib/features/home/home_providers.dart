import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

// Written by hand rather than with riverpod_generator: the Drift row classes
// (Home, Room) live in a generated part file, which the Riverpod generator
// cannot see in the same build phase.

/// The single home of v1, or null before onboarding.
final currentHomeProvider = StreamProvider<Home?>(
  (ref) => ref.watch(appDatabaseProvider).homesDao.watchCurrentHome(),
);

class HomeRepository {
  HomeRepository(this._db);

  final AppDatabase _db;

  Future<String> createHome({
    required String name,
    String? address,
    required PropertyType propertyType,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    await _db.homesDao.insertHome(
      HomesCompanion.insert(
        id: id,
        name: name.trim(),
        address: Value(_nullIfBlank(address)),
        propertyType: propertyType,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  static String? _nullIfBlank(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(appDatabaseProvider)),
);
