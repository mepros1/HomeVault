import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../db/database.dart';
import 'image_prep.dart';

/// Item attachments (spec §3.5): receipt, label, extra photos.
///
/// Files live under `<base>/attachments/<itemId>/<id>.jpg` with a thumbnail
/// beside them; paths in `attachments.file_path` are relative to [baseDir]
/// like captures. Attachments are never uploaded anywhere.
class AttachmentStore {
  AttachmentStore(this._db, {required Future<Directory> Function() baseDir})
      : _baseDir = baseDir;

  final AppDatabase _db;
  final Future<Directory> Function() _baseDir;

  Future<Attachment> add({
    required String itemId,
    required AttachmentKind kind,
    required Uint8List bytes,
    String? ocrText,
  }) async {
    // Decode once: rejects non-images before anything is written.
    await inspectOriginal(bytes);
    final thumb = await makeThumbnail(bytes);

    final id = const Uuid().v4();
    final relDir = p.posix.join('attachments', itemId);
    final relFile = p.posix.join(relDir, '$id.jpg');
    final relThumb = p.posix.join(relDir, '${id}_thumb.jpg');

    final base = await _baseDir();
    await Directory(p.join(base.path, relDir)).create(recursive: true);
    await File(p.join(base.path, relFile)).writeAsBytes(bytes, flush: true);
    await File(p.join(base.path, relThumb)).writeAsBytes(thumb, flush: true);

    final attachment = Attachment(
      id: id,
      itemId: itemId,
      kind: kind,
      filePath: relFile,
      ocrText: ocrText,
      createdAt: DateTime.now(),
    );
    await _db.itemsDao.addAttachment(attachment.toCompanion(false));
    return attachment;
  }

  Future<void> setOcrText(String attachmentId, String? text) =>
      _db.itemsDao.updateAttachment(
        attachmentId,
        AttachmentsCompanion(ocrText: Value(text)),
      );

  Future<void> delete(String attachmentId) async {
    final a = await _db.itemsDao.getAttachment(attachmentId);
    if (a == null) return;
    final base = await _baseDir();
    for (final rel in [a.filePath, thumbPathFor(a.filePath)]) {
      final f = File(p.join(base.path, rel));
      if (await f.exists()) await f.delete();
    }
    await _db.itemsDao.deleteAttachment(attachmentId);
  }

  /// `attachments/<item>/<id>.jpg` -> `attachments/<item>/<id>_thumb.jpg`.
  static String thumbPathFor(String filePath) =>
      filePath.replaceFirst(RegExp(r'\.jpg$'), '_thumb.jpg');

  Future<String> absolutePath(String relative) async =>
      p.join((await _baseDir()).path, relative);
}
