import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/constants.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/media/capture_store.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  late CaptureStore store;

  /// A real JPEG so decoding, hashing and thumbnailing run end to end.
  final Uint8List landscape = img.encodeJpg(
    img.fill(img.Image(width: 1600, height: 900), color: img.ColorRgb8(200, 30, 30)),
    quality: 85,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_captures_');
    store = CaptureStore(db, baseDir: () async => base);
    final now = DateTime.utc(2026, 9, 21);
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'r', homeId: 'h', name: 'Kitchen', roomType: RoomType.kitchen, orderIndex: 0, createdAt: now));
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  test('stores original, thumbnail, hash and dimensions; room becomes captured', () async {
    final capture = await store.addCapture(roomId: 'r', originalBytes: landscape);

    expect(capture.sha256, sha256.convert(landscape).toString());
    expect(capture.width, 1600);
    expect(capture.height, 900);
    expect(capture.filePath, 'captures/r/${capture.id}.jpg');
    expect(capture.isCloseup, isFalse);

    final original = File(p.join(base.path, capture.filePath));
    expect(await original.readAsBytes(), landscape);

    final thumb = img.decodeImage(await File(p.join(base.path, capture.thumbPath!)).readAsBytes())!;
    expect(thumb.width, 320);
    expect(thumb.height, 180);

    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.captured);
    expect(await db.capturesDao.countForRoom('r'), 1);
  });

  test('close-up flag and taken-at are persisted', () async {
    final at = DateTime.utc(2026, 9, 21, 10, 30);
    final c = await store.addCapture(
        roomId: 'r', originalBytes: landscape, isCloseup: true, takenAt: at);
    expect(c.isCloseup, isTrue);
    expect((await db.capturesDao.getCapture(c.id))!.takenAt.toUtc(), at);
  });

  test('enforces the per-room maximum', () async {
    for (var i = 0; i < Limits.maxCapturesPerRoom; i++) {
      await store.addCapture(roomId: 'r', originalBytes: landscape);
    }
    expect(
      () => store.addCapture(roomId: 'r', originalBytes: landscape),
      throwsA(isA<CaptureLimitReached>()),
    );
  });

  test('rejects bytes that are not an image', () async {
    expect(
      () => store.addCapture(roomId: 'r', originalBytes: Uint8List.fromList([1, 2, 3])),
      throwsA(isA<FormatException>()),
    );
    expect(await db.capturesDao.countForRoom('r'), 0);
  });

  test('delete removes files and resets an un-analyzed room to empty', () async {
    final c = await store.addCapture(roomId: 'r', originalBytes: landscape);
    final file = File(p.join(base.path, c.filePath));
    expect(await file.exists(), isTrue);

    await store.deleteCapture(c.id);

    expect(await file.exists(), isFalse);
    expect(await File(p.join(base.path, c.thumbPath!)).exists(), isFalse);
    expect(await db.capturesDao.countForRoom('r'), 0);
    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.empty);
  });

  test('delete keeps the status of an analyzed room', () async {
    final c = await store.addCapture(roomId: 'r', originalBytes: landscape);
    await db.roomsDao.setStatus('r', RoomStatus.analyzed);

    await store.deleteCapture(c.id);

    expect((await db.roomsDao.getRoom('r'))!.status, RoomStatus.analyzed);
  });
}
