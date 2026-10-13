import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/media/storage_janitor.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  final now = DateTime.utc(2026, 9, 27, 12);

  Future<void> touch(String rel, {DateTime? modified}) async {
    final f = File(p.join(base.path, rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]);
    if (modified != null) await f.setLastModified(modified);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_janitor_');
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'live-room', homeId: 'h', name: 'Kitchen', roomType: RoomType.kitchen,
        orderIndex: 0, createdAt: now));
    await db.into(db.items).insert(ItemsCompanion.insert(
        id: 'live-item', roomId: 'live-room', name: 'Fridge', category: ItemCategory.appliances,
        createdAt: now, updatedAt: now));
    await db.reportsDao.insertReport(ReportsCompanion.insert(
        id: 'r1', homeId: 'h', generatedAt: now, pdfPath: 'reports/live.pdf',
        itemCount: 1, totalLow: 1, totalHigh: 2));
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  test('removes directories and files without rows, keeps everything referenced', () async {
    await touch('captures/live-room/a.jpg');
    await touch('captures/gone-room/b.jpg');
    await touch('attachments/live-item/c.jpg');
    await touch('attachments/gone-item/d.jpg');
    await touch('reports/live.pdf');
    await touch('reports/orphan.pdf');
    await touch('reports/fresh.csv', modified: now.subtract(const Duration(hours: 2)));
    await touch('reports/old.csv', modified: now.subtract(const Duration(days: 2)));

    final removed = await StorageJanitor(db, baseDir: () async => base).sweep(now: now);

    expect(removed, 4);
    expect(await Directory(p.join(base.path, 'captures/live-room')).exists(), isTrue);
    expect(await Directory(p.join(base.path, 'captures/gone-room')).exists(), isFalse);
    expect(await Directory(p.join(base.path, 'attachments/live-item')).exists(), isTrue);
    expect(await Directory(p.join(base.path, 'attachments/gone-item')).exists(), isFalse);
    expect(await File(p.join(base.path, 'reports/live.pdf')).exists(), isTrue);
    expect(await File(p.join(base.path, 'reports/orphan.pdf')).exists(), isFalse);
    expect(await File(p.join(base.path, 'reports/fresh.csv')).exists(), isTrue);
    expect(await File(p.join(base.path, 'reports/old.csv')).exists(), isFalse);
  });

  test('is a no-op on a fresh install without directories', () async {
    expect(await StorageJanitor(db, baseDir: () async => base).sweep(now: now), 0);
  });

  test('deleting a room leaves its files for the sweep to collect', () async {
    await touch('captures/live-room/a.jpg');
    await touch('attachments/live-item/c.jpg');
    await db.roomsDao.deleteRoom('live-room');

    expect(await StorageJanitor(db, baseDir: () async => base).sweep(now: now), 2);
    expect(await Directory(p.join(base.path, 'captures')).list().length, 0);
    expect(await Directory(p.join(base.path, 'attachments')).list().length, 0);
  });
}
