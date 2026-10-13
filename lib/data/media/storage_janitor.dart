import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';

/// Removes files whose database rows are gone.
///
/// Rows are deleted by cascades (room -> captures -> items -> attachments)
/// and by undoable deletes on the review screen, so files are not removed
/// synchronously. Instead this sweep runs at app start and after a room is
/// deleted: any `captures/<roomId>` or `attachments/<itemId>` directory with
/// no matching row goes, as do PDFs without a `reports` row and CSVs older
/// than a day (they are never recorded, only shared).
class StorageJanitor {
  StorageJanitor(this._db, {required Future<Directory> Function() baseDir})
      : _baseDir = baseDir;

  final AppDatabase _db;
  final Future<Directory> Function() _baseDir;

  static const Duration csvRetention = Duration(days: 1);

  /// Returns how many entries were removed.
  Future<int> sweep({DateTime? now}) async {
    final base = await _baseDir();
    var removed = 0;

    final roomIds = (await _db.select(_db.rooms).get()).map((r) => r.id).toSet();
    removed += await _pruneDirs(Directory(p.join(base.path, 'captures')), roomIds);

    final itemIds = (await _db.select(_db.items).get()).map((i) => i.id).toSet();
    removed += await _pruneDirs(Directory(p.join(base.path, 'attachments')), itemIds);

    final reports = Directory(p.join(base.path, 'reports'));
    if (await reports.exists()) {
      final keep = (await _db.select(_db.reports).get())
          .map((r) => p.basename(r.pdfPath))
          .toSet();
      final cutoff = (now ?? DateTime.now()).subtract(csvRetention);
      await for (final entry in reports.list()) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        final stale = name.endsWith('.pdf')
            ? !keep.contains(name)
            : name.endsWith('.csv') && (await entry.lastModified()).isBefore(cutoff);
        if (stale) {
          await entry.delete();
          removed++;
        }
      }
    }
    return removed;
  }

  Future<int> _pruneDirs(Directory parent, Set<String> liveIds) async {
    if (!await parent.exists()) return 0;
    var removed = 0;
    await for (final entry in parent.list()) {
      if (entry is Directory && !liveIds.contains(p.basename(entry.path))) {
        await entry.delete(recursive: true);
        removed++;
      }
    }
    return removed;
  }
}
