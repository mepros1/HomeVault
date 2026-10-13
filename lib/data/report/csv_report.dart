import '../../core/enums.dart';
import 'report_data.dart';

/// Flat export of every item field (spec §3.7). RFC 4180 quoting; one row
/// per item; a header row first. Pro only, enforced by the repository.
class CsvReportGenerator {
  static const List<String> columns = [
    'room',
    'room_type',
    'name',
    'category',
    'brand',
    'model',
    'serial',
    'qty',
    'condition',
    'purchase_date',
    'purchase_price',
    'est_low',
    'est_high',
    'line_low',
    'line_high',
    'currency',
    'confidence',
    'is_high_value',
    'review_status',
    'user_edited',
    'note',
    'source_capture_sha256',
    'created_at',
    'updated_at',
  ];

  String generate(ReportData data) {
    final buffer = StringBuffer()..writeln(columns.map(_escape).join(','));
    for (final room in data.rooms) {
      final captureHashes = {for (final c in room.captures) c.id: c.sha256};
      for (final item in room.items) {
        buffer.writeln([
          room.room.name,
          room.room.roomType == RoomType.custom ? 'Custom' : room.room.roomType.label,
          item.name,
          item.category.label,
          item.brand ?? '',
          item.model ?? '',
          item.serial ?? '',
          '${item.qty}',
          item.condition?.wire ?? '',
          item.purchaseDate?.toIso8601String().substring(0, 10) ?? '',
          _num(item.purchasePrice),
          _num(item.estLow),
          _num(item.estHigh),
          _num(lineLow(item)),
          _num(lineHigh(item)),
          item.currency,
          _num(item.confidence),
          item.isHighValue ? 'true' : 'false',
          item.reviewStatus.name,
          item.userEdited ? 'true' : 'false',
          item.note ?? '',
          captureHashes[item.sourceCaptureId] ?? '',
          item.createdAt.toUtc().toIso8601String(),
          item.updatedAt.toUtc().toIso8601String(),
        ].map(_escape).join(','));
      }
    }
    return buffer.toString();
  }

  static String _num(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  static String _escape(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n') && !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
