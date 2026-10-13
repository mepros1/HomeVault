import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/db/database.dart';
import 'package:homevault/data/entitlement.dart';
import 'package:homevault/data/media/capture_store.dart';
import 'package:homevault/data/report/csv_report.dart';
import 'package:homevault/data/report/pdf_report.dart';
import 'package:homevault/data/report/report_data.dart';
import 'package:homevault/data/report/report_repository.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  late CaptureStore store;
  final now = DateTime.utc(2026, 9, 21, 12);

  Future<(pw.Font, pw.Font)> fileFonts() async {
    ByteData data(String name) =>
        ByteData.view(File('assets/fonts/$name').readAsBytesSync().buffer);
    return (pw.Font.ttf(data('NotoSans-Regular.ttf')), pw.Font.ttf(data('NotoSans-Bold.ttf')));
  }

  final Uint8List jpeg = img.encodeJpg(
    img.fill(img.Image(width: 640, height: 480), color: img.ColorRgb8(90, 140, 60)),
    quality: 80,
  );

  ReportRepository repo({Entitlement entitlement = Entitlement.free}) => ReportRepository(
        db: db,
        captures: store,
        pdf: PdfReportGenerator(fonts: fileFonts),
        baseDir: () async => base,
        entitlement: () => entitlement,
        clock: () => now,
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_report_');
    store = CaptureStore(db, baseDir: () async => base);

    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'Maple House', address: const Value('12 Maple St, Springfield'),
        propertyType: PropertyType.house, createdAt: now, updatedAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'living', homeId: 'h', name: 'Living Room', roomType: RoomType.livingRoom,
        orderIndex: 0, status: const Value(RoomStatus.reviewed), createdAt: now));
    await db.roomsDao.insertRoom(RoomsCompanion.insert(
        id: 'bed', homeId: 'h', name: 'Bedroom', roomType: RoomType.bedroom,
        orderIndex: 1, status: const Value(RoomStatus.analyzed), createdAt: now));
    final capture = await store.addCapture(roomId: 'living', originalBytes: jpeg, takenAt: now);

    ItemsCompanion item(String id, String room, String name, ItemCategory cat, double low, double high,
            {int qty = 1, bool highValue = false, ReviewStatus status = ReviewStatus.accepted, String? capture}) =>
        ItemsCompanion.insert(
          id: id, roomId: room, name: name, category: cat, qty: Value(qty),
          estLow: Value(low), estHigh: Value(high), confidence: const Value(0.8),
          isHighValue: Value(highValue), reviewStatus: Value(status),
          sourceCaptureId: Value(capture), createdAt: now, updatedAt: now,
        );
    await db.batch((b) => b.insertAll(db.items, [
          item('tv', 'living', 'Television, 55"', ItemCategory.electronics, 400, 900, capture: capture.id),
          item('chairs', 'living', 'Dining chair', ItemCategory.furniture, 50, 120, qty: 6),
          item('ring', 'bed', 'Gold ring', ItemCategory.jewelryWatches, 300, 800, highValue: true),
          item('lamp', 'bed', 'Lamp', ItemCategory.homeDecor, 20, 60, status: ReviewStatus.pending),
        ]));
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  test('report data: totals multiply by quantity, summaries and high-value section', () async {
    final data = (await ReportBuilder(db).build('h', now: now))!;

    expect(data.rooms.map((r) => r.room.name), ['Living Room', 'Bedroom']);
    expect(data.itemCount, 4);
    expect(data.captureCount, 1);
    expect(data.totalLow, 400 + 6 * 50 + 300 + 20);
    expect(data.totalHigh, 900 + 6 * 120 + 800 + 60);
    expect(data.allItems.first.$2.name, 'Television, 55"');
    expect(data.highValueItems.single.$2.name, 'Gold ring');
    expect(data.unreviewedCount, 1);

    final furniture = data.categorySummary.firstWhere((c) => c.category == ItemCategory.furniture);
    expect(furniture.count, 1);
    expect(furniture.totalHigh, 720);
    expect(data.categorySummary.first.category, ItemCategory.electronics, reason: 'sorted by value');
  });

  test('csv: header, one row per item, RFC 4180 quoting', () async {
    final data = (await ReportBuilder(db).build('h', now: now))!;
    final csv = CsvReportGenerator().generate(data);
    final lines = csv.trim().split('\n');

    expect(lines.first.split(','), CsvReportGenerator.columns);
    expect(lines, hasLength(5));
    expect(lines[1], startsWith('Living Room,Living Room,"Television, 55""",Electronics,'));
    final chairs = lines.firstWhere((l) => l.contains('Dining chair'));
    expect(chairs, contains(',6,'));
    expect(chairs, contains(',300,720,USD,'));
    final captures = await db.capturesDao.forRoom('living');
    expect(lines[1], contains(captures.single.sha256));
  });

  test('pdf: renders with thumbnails; free gets a watermark, pro does not', () async {
    final data = (await ReportBuilder(db).build('h', now: now))!;
    Future<Uint8List?> thumb(Capture c) async => (await store.thumbFile(c))!.readAsBytes();
    final gen = PdfReportGenerator(fonts: fileFonts);

    final free = await gen.generate(data, watermark: true, thumbOf: thumb);
    final pro = await gen.generate(data, watermark: false, thumbOf: thumb);

    expect(String.fromCharCodes(free.take(5)), '%PDF-');
    expect(free.length, greaterThan(20000));
    expect(pro.length, greaterThan(20000));
    expect(free.length, isNot(pro.length), reason: 'watermark changes the content streams');
  });

  test('repository: pdf is written and recorded; csv is pro only', () async {
    final report = await repo().generatePdf('h');
    final file = File(p.join(base.path, report.pdfPath));
    expect(await file.exists(), isTrue);
    expect(report.pdfPath, startsWith('reports/HomeVault-Maple-House-2026-09-21-'));
    expect(report.pdfPath, endsWith('.pdf'));
    expect(report.itemCount, 4);
    expect(report.totalHigh, 900 + 720 + 800 + 60);
    expect((await db.reportsDao.watchForHome('h').first).single.id, report.id);

    expect(() => repo().generateCsv('h'), throwsA(isA<ProRequired>()));
    final rel = await repo(entitlement: Entitlement.pro).generateCsv('h');
    expect(await File(p.join(base.path, rel)).readAsString(), contains('Gold ring'));

    await repo().deleteReport(report);
    expect(await file.exists(), isFalse);
    expect(await db.reportsDao.watchForHome('h').first, isEmpty);
  });
}
