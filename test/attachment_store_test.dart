import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/media/attachment_store.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  late AttachmentStore store;

  final Uint8List jpeg = img.encodeJpg(
    img.fill(img.Image(width: 800, height: 600), color: img.ColorRgb8(240, 240, 240)),
    quality: 85,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_attachments_');
    store = AttachmentStore(db, baseDir: () async => base);
    final now = DateTime.utc(2026, 9, 21);
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'r', homeId: 'h', name: 'Kitchen', roomType: RoomType.kitchen, orderIndex: 0, createdAt: now));
    await db.into(db.items).insert(ItemsCompanion.insert(
        id: 'i', roomId: 'r', name: 'Fridge', category: ItemCategory.appliances,
        createdAt: now, updatedAt: now));
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  test('stores original and thumbnail, records kind and OCR text', () async {
    final a = await store.add(itemId: 'i', kind: AttachmentKind.label, bytes: jpeg);
    expect(a.filePath, 'attachments/i/${a.id}.jpg');
    expect(await File(p.join(base.path, a.filePath)).length(), jpeg.length);
    expect(await File(p.join(base.path, AttachmentStore.thumbPathFor(a.filePath))).exists(), isTrue);

    await store.setOcrText(a.id, 'S/N: ABC123456');
    final rows = await db.itemsDao.watchAttachments('i').first;
    expect(rows.single.kind, AttachmentKind.label);
    expect(rows.single.ocrText, 'S/N: ABC123456');
  });

  test('rejects non-images without writing anything', () async {
    expect(
      () => store.add(itemId: 'i', kind: AttachmentKind.receipt, bytes: Uint8List.fromList([1, 2])),
      throwsA(isA<FormatException>()),
    );
    expect(await db.itemsDao.watchAttachments('i').first, isEmpty);
  });

  test('delete removes both files and the row; deleting the item cascades rows', () async {
    final a = await store.add(itemId: 'i', kind: AttachmentKind.receipt, bytes: jpeg);
    await store.delete(a.id);
    expect(await File(p.join(base.path, a.filePath)).exists(), isFalse);
    expect(await db.itemsDao.watchAttachments('i').first, isEmpty);

    await store.add(itemId: 'i', kind: AttachmentKind.extra, bytes: jpeg);
    await db.itemsDao.deleteItem('i');
    expect(await db.itemsDao.watchAttachments('i').first, isEmpty);
  });
}
