import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../db/database.dart';
import 'image_prep.dart';

/// Thrown when a room already holds [Limits.maxCapturesPerRoom] photos.
class CaptureLimitReached implements Exception {
  const CaptureLimitReached(this.max);

  final int max;
}

/// Owns capture files and rows (spec §3.2).
///
/// Originals are stored untouched under `<base>/captures/<roomId>/<id>.jpg`
/// next to a baked-orientation thumbnail. `captures.file_path` and
/// `thumb_path` are stored relative to [baseDir] so the app directory can
/// move (backup/restore, storage migration) without breaking rows. The
/// SHA-256 of the original is the evidence hash and the idempotency-key input.
class CaptureStore {
  CaptureStore(this._db, {required this._baseDir});

  final AppDatabase _db;
  final Future<Directory> Function() _baseDir;

  Future<Capture> addCapture({
    required String roomId,
    required Uint8List originalBytes,
    bool isCloseup = false,
    DateTime? takenAt,
  }) async {
    final count = await _db.capturesDao.countForRoom(roomId);
    if (count >= Limits.maxCapturesPerRoom) {
      throw const CaptureLimitReached(Limits.maxCapturesPerRoom);
    }

    final info = await inspectOriginal(originalBytes);
    final thumb = await makeThumbnail(originalBytes);

    final id = const Uuid().v4();
    final relDir = p.posix.join('captures', roomId);
    final relFile = p.posix.join(relDir, '$id.jpg');
    final relThumb = p.posix.join(relDir, '${id}_thumb.jpg');

    final base = await _baseDir();
    await Directory(p.join(base.path, relDir)).create(recursive: true);
    await File(p.join(base.path, relFile)).writeAsBytes(originalBytes, flush: true);
    await File(p.join(base.path, relThumb)).writeAsBytes(thumb, flush: true);

    final capture = Capture(
      id: id,
      roomId: roomId,
      filePath: relFile,
      thumbPath: relThumb,
      takenAt: takenAt ?? DateTime.now(),
      lat: null,
      lng: null,
      sha256: info.sha256Hex,
      width: info.width,
      height: info.height,
      analyzed: false,
      isCloseup: isCloseup,
    );

    await _db.transaction(() async {
      await _db.capturesDao.insertCapture(capture.toCompanion(false));
      final room = await _db.roomsDao.getRoom(roomId);
      if (room != null && room.status == RoomStatus.empty) {
        await _db.roomsDao.setStatus(roomId, RoomStatus.captured);
      }
    });
    return capture;
  }

  /// Removes files and the row. A room that loses its last photo before
  /// analysis goes back to `empty`; analyzed rooms keep their status.
  Future<void> deleteCapture(String id) async {
    final capture = await _db.capturesDao.getCapture(id);
    if (capture == null) return;

    final base = await _baseDir();
    for (final rel in [capture.filePath, capture.thumbPath]) {
      if (rel == null) continue;
      final f = File(p.join(base.path, rel));
      if (await f.exists()) await f.delete();
    }

    await _db.transaction(() async {
      await _db.capturesDao.deleteCapture(id);
      final remaining = await _db.capturesDao.countForRoom(capture.roomId);
      final room = await _db.roomsDao.getRoom(capture.roomId);
      if (remaining == 0 && room?.status == RoomStatus.captured) {
        await _db.roomsDao.setStatus(capture.roomId, RoomStatus.empty);
      }
    });
  }

  Future<File> originalFile(Capture c) async =>
      File(p.join((await _baseDir()).path, c.filePath));

  Future<File?> thumbFile(Capture c) async {
    final rel = c.thumbPath;
    if (rel == null) return null;
    return File(p.join((await _baseDir()).path, rel));
  }

  Future<Uint8List> readOriginal(Capture c) async =>
      (await originalFile(c)).readAsBytes();

  /// Absolute path helper for widgets that already hold a row.
  Future<String> absolutePath(String relative) async =>
      p.join((await _baseDir()).path, relative);
}
