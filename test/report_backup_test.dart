import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/api/api_errors.dart';
import 'package:homevault/data/backup/report_backup_client.dart';
import 'package:homevault/data/backup/report_backup_service.dart';
import 'package:homevault/data/db/database.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  final endpoint = Uri.parse('http://server/v1/backups');

  Map<String, dynamic> backupJson(String id) => {
        'id': id,
        'file_name': 'HomeVault-H-2026-09-28-$id.pdf',
        'size_bytes': 9,
        'sha256': 'x',
        'generated_at': '2026-09-28T10:00:00Z',
        'item_count': 2,
        'total_low': 10.0,
        'total_high': 40.0,
        'created_at': '2026-09-28T10:00:01Z',
      };

  Future<void> seedReport(String id) async {
    final rel = p.posix.join('reports', 'HomeVault-H-2026-09-28-$id.pdf');
    final file = File(p.join(base.path, rel));
    await file.parent.create(recursive: true);
    await file.writeAsString('%PDF-1.7 x');
    await db.reportsDao.insertReport(ReportsCompanion.insert(
      id: id,
      homeId: 'h',
      generatedAt: DateTime.utc(2026, 9, 28, 10),
      pdfPath: rel,
      itemCount: 2,
      totalLow: 10,
      totalHigh: 40,
    ));
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('homevault_backup_');
    final now = DateTime.utc(2026, 9, 28);
    await db.homesDao.insertHome(HomesCompanion.insert(
        id: 'h', name: 'H', propertyType: PropertyType.house, createdAt: now, updatedAt: now));
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  ReportBackupService service(ReportBackupClient client, {bool enabled = true}) =>
      ReportBackupService(db, client: client, baseDir: () async => base, enabled: () => enabled);

  test('uploads pending reports as multipart with metadata and marks them backed up', () async {
    await seedReport('a');
    await seedReport('b');
    final seen = <http.BaseRequest>[];
    final client = ReportBackupClient(
      baseEndpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((req) async {
        seen.add(req);
        expect(req.headers['Authorization'], 'Bearer tok');
        expect(req.headers['content-type'], startsWith('multipart/form-data'));
        expect(req.body, contains('name="file"'));
        expect(req.body, contains('%PDF-1.7'));
        expect(req.body, contains('2026-09-28T10:00:00.000Z'));
        return http.Response(jsonEncode(backupJson('a')), 200);
      }),
    );

    await service(client).backupPending();

    expect(seen, hasLength(2));
    expect(await db.reportsDao.pendingBackup(), isEmpty);
    expect((await db.reportsDao.getReport('a'))!.backedUpAt, isNotNull);

    // Nothing left: no request.
    await service(client).backupPending();
    expect(seen, hasLength(2));
  });

  test('disabled backup uploads nothing; a full cloud leaves reports pending', () async {
    await seedReport('a');
    var calls = 0;
    final full = ReportBackupClient(
      baseEndpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{"error":"backup_limit","message":"full"}', 409);
      }),
    );

    await service(full, enabled: false).backupPending();
    expect(calls, 0);

    await service(full).backupPending();
    expect(calls, 1);
    expect(await db.reportsDao.pendingBackup(), hasLength(1));
    expect(await service(full).backup((await db.reportsDao.getReport('a'))!), isFalse);
  });

  test('list, download, transfer code and claim map the wire format and errors', () async {
    final client = ReportBackupClient(
      baseEndpoint: endpoint,
      accessToken: () => 'tok',
      httpClient: MockClient((req) async {
        switch ('${req.method} ${req.url.path}') {
          case 'GET /v1/backups':
            return http.Response(jsonEncode({'backups': [backupJson('a')], 'max_count': 20}), 200);
          case 'GET /v1/backups/a':
            return http.Response.bytes([0x25, 0x50, 0x44, 0x46], 200);
          case 'POST /v1/backups/transfer-code':
            return http.Response(jsonEncode({'code': 'ABCD2345', 'expires_at': '2026-09-28T10:15:00Z'}), 200);
          case 'POST /v1/backups/claim':
            final code = (jsonDecode(req.body) as Map)['code'];
            return code == 'ABCD2345'
                ? http.Response('{"moved":2}', 200)
                : http.Response('{"error":"transfer_code_invalid"}', 404);
          case 'DELETE /v1/backups/a':
            return http.Response('', 204);
        }
        return http.Response('nope', 500);
      }),
    );

    final list = await client.list();
    expect(list.single.id, 'a');
    expect(list.single.itemCount, 2);
    expect(await client.download('a'), [0x25, 0x50, 0x44, 0x46]);
    expect((await client.transferCode()).code, 'ABCD2345');
    expect(await client.claim('ABCD2345'), 2);
    await client.delete('a');
    await expectLater(client.claim('WRONG'), throwsA(isA<TransferCodeInvalidException>()));
  });
}
