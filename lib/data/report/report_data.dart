import '../../core/constants.dart';
import '../../core/enums.dart';
import '../db/database.dart';

/// One room with everything the report needs about it.
class ReportRoom {
  const ReportRoom({required this.room, required this.items, required this.captures});

  final Room room;

  /// Review order: est_high DESC.
  final List<Item> items;
  final List<Capture> captures;

  double get totalLow => items.fold(0, (sum, i) => sum + lineLow(i));
  double get totalHigh => items.fold(0, (sum, i) => sum + lineHigh(i));
}

/// Per-category line for the summary table.
class CategorySummary {
  const CategorySummary({
    required this.category,
    required this.count,
    required this.totalLow,
    required this.totalHigh,
  });

  final ItemCategory category;
  final int count;
  final double totalLow;
  final double totalHigh;
}

/// Everything the PDF and CSV renderers need, computed once (spec §3.7).
class ReportData {
  ReportData({
    required this.home,
    required this.rooms,
    required this.generatedAt,
    this.currency = Defaults.currency,
  });

  final Home home;
  final List<ReportRoom> rooms;
  final DateTime generatedAt;
  final String currency;

  int get itemCount => rooms.fold(0, (n, r) => n + r.items.length);
  int get captureCount => rooms.fold(0, (n, r) => n + r.captures.length);
  double get totalLow => rooms.fold(0, (sum, r) => sum + r.totalLow);
  double get totalHigh => rooms.fold(0, (sum, r) => sum + r.totalHigh);

  /// All items, most expensive first, with their room.
  List<(ReportRoom, Item)> get allItems {
    final rows = [
      for (final r in rooms)
        for (final i in r.items) (r, i),
    ];
    rows.sort((a, b) => (b.$2.estHigh ?? 0).compareTo(a.$2.estHigh ?? 0));
    return rows;
  }

  List<(ReportRoom, Item)> get highValueItems =>
      allItems.where((e) => e.$2.isHighValue).toList();

  int get unreviewedCount => rooms.fold(
      0, (n, r) => n + r.items.where((i) => i.reviewStatus == ReviewStatus.pending).length);

  List<CategorySummary> get categorySummary {
    final byCategory = <ItemCategory, List<Item>>{};
    for (final r in rooms) {
      for (final i in r.items) {
        byCategory.putIfAbsent(i.category, () => []).add(i);
      }
    }
    final rows = [
      for (final entry in byCategory.entries)
        CategorySummary(
          category: entry.key,
          count: entry.value.length,
          totalLow: entry.value.fold(0, (s, i) => s + lineLow(i)),
          totalHigh: entry.value.fold(0, (s, i) => s + lineHigh(i)),
        ),
    ];
    rows.sort((a, b) => b.totalHigh.compareTo(a.totalHigh));
    return rows;
  }
}

/// Replacement-cost range for the whole line: estimate × quantity.
double lineLow(Item i) => (i.estLow ?? 0) * i.qty;
double lineHigh(Item i) => (i.estHigh ?? 0) * i.qty;

/// Reads the home, its rooms in order, items in review order and captures.
class ReportBuilder {
  ReportBuilder(this._db);

  final AppDatabase _db;

  Future<ReportData?> build(String homeId, {DateTime? now}) async {
    final home = await (_db.select(_db.homes)..where((h) => h.id.equals(homeId))).getSingleOrNull();
    if (home == null) return null;

    final rooms = await _db.roomsDao.watchRoomsForHome(homeId).first;
    final reportRooms = <ReportRoom>[];
    for (final room in rooms) {
      reportRooms.add(ReportRoom(
        room: room,
        items: await _db.itemsDao.watchItemsForRoom(room.id).first,
        captures: await _db.capturesDao.forRoom(room.id),
      ));
    }
    return ReportData(home: home, rooms: reportRooms, generatedAt: now ?? DateTime.now());
  }
}
