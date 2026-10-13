import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../db/database.dart';
import 'report_data.dart';

/// Loads the report font pair; the app reads assets, tests read files.
typedef FontLoader = Future<(pw.Font regular, pw.Font bold)> Function();

/// Thumbnail bytes for a capture, or null when the file is missing.
typedef ThumbLoader = Future<Uint8List?> Function(Capture capture);

/// PDF layout from spec §3.7: title, room summary, category summary,
/// high-value section, full item table with thumbnails, photo appendix,
/// disclaimer. Free tier gets a watermark on every page.
class PdfReportGenerator {
  PdfReportGenerator({required FontLoader fonts}) : _fonts = fonts;

  final FontLoader _fonts;

  static const String watermarkText = 'HOMEVAULT FREE';

  Future<Uint8List> generate(
    ReportData data, {
    required bool watermark,
    required ThumbLoader thumbOf,
  }) async {
    final (regular, bold) = await _fonts();
    final money = NumberFormat.simpleCurrency(name: data.currency, decimalDigits: 0);
    final date = DateFormat.yMMMd();
    final dateTime = DateFormat.yMMMd().add_Hm();

    // Thumbnails are decoded once and shared between the item table and the appendix.
    final images = <String, pw.MemoryImage>{};
    for (final room in data.rooms) {
      for (final c in room.captures) {
        final bytes = await thumbOf(c);
        if (bytes != null) images[c.id] = pw.MemoryImage(bytes);
      }
    }

    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(
      theme: theme,
      title: 'HomeVault inventory – ${data.home.name}',
      author: 'HomeVault',
    );

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      buildBackground: watermark
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.12,
                    child: pw.Watermark.text(
                      watermarkText,
                      style: pw.TextStyle(fontSize: 72, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              )
          : null,
    );

    pw.Widget footer(pw.Context context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'HomeVault · ${data.home.name} · ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        );

    String range(double low, double high) => '${money.format(low)} – ${money.format(high)}';
    String roomLabel(Room r) => r.name;

    // 1. Title page ---------------------------------------------------------
    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 120),
            pw.Text('Home contents inventory',
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(data.home.name, style: const pw.TextStyle(fontSize: 20)),
            if (data.home.address != null)
              pw.Text(data.home.address!, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 32),
            _kv('Generated', dateTime.format(data.generatedAt)),
            _kv('Property type', data.home.propertyType.label),
            _kv('Rooms', '${data.rooms.length}'),
            _kv('Items', '${data.itemCount}'),
            _kv('Photos', '${data.captureCount}'),
            _kv('Estimated replacement value', range(data.totalLow, data.totalHigh)),
            if (data.unreviewedCount > 0)
              _kv('Not yet reviewed', '${data.unreviewedCount} items'),
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(Disclaimer.short, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
    );

    // 2–4. Summaries and high-value section ----------------------------------
    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        footer: footer,
        maxPages: 200,
        build: (context) => [
          pw.Header(level: 0, text: 'Summary by room'),
          pw.TableHelper.fromTextArray(
            headers: const ['Room', 'Items', 'Photos', 'Estimated value'],
            data: [
              for (final r in data.rooms)
                [
                  roomLabel(r.room),
                  '${r.items.length}',
                  '${r.captures.length}',
                  range(r.totalLow, r.totalHigh),
                ],
              ['Total', '${data.itemCount}', '${data.captureCount}', range(data.totalLow, data.totalHigh)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: const {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 24),
          pw.Header(level: 0, text: 'Summary by category'),
          pw.TableHelper.fromTextArray(
            headers: const ['Category', 'Items', 'Estimated value'],
            data: [
              for (final c in data.categorySummary)
                [c.category.label, '${c.count}', range(c.totalLow, c.totalHigh)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: const {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 24),
          pw.Header(level: 0, text: 'High-value items'),
          pw.Paragraph(
            text:
                'Items estimated at ${money.format(Limits.defaultHighValueThreshold)} or more, and jewelry, art or collectibles. Standard policies often cap these; check whether they need separate coverage.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
          if (data.highValueItems.isEmpty)
            pw.Paragraph(text: 'None.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Item', 'Room', 'Category', 'Brand / model', 'Qty', 'Estimated value'],
              data: [
                for (final (r, i) in data.highValueItems)
                  [
                    i.name,
                    roomLabel(r.room),
                    i.category.label,
                    [i.brand, i.model].whereType<String>().join(' '),
                    '${i.qty}',
                    range(lineLow(i), lineHigh(i)),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: const {4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
            ),
        ],
      ),
    );

    // 5. Full item table with thumbnails --------------------------------------
    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        footer: footer,
        maxPages: 200,
        build: (context) => [
          pw.Header(level: 0, text: 'All items'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(44),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.8),
              4: pw.FlexColumnWidth(2),
              5: pw.FixedColumnWidth(26),
              6: pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final h in const ['', 'Item', 'Room', 'Category', 'Brand / model / serial', 'Qty', 'Estimated value'])
                    _cell(h, bold: true),
                ],
              ),
              for (final (r, i) in data.allItems)
                pw.TableRow(
                  verticalAlignment: pw.TableCellVerticalAlignment.middle,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(2),
                      child: i.sourceCaptureId != null && images[i.sourceCaptureId] != null
                          ? pw.Image(images[i.sourceCaptureId]!, width: 40, height: 30, fit: pw.BoxFit.cover)
                          : pw.SizedBox(width: 40, height: 30),
                    ),
                    _cell([
                      i.name,
                      if (i.condition != null) 'Condition: ${i.condition!.wire}',
                      if (i.note != null) i.note!,
                      if (i.reviewStatus == ReviewStatus.pending) 'Not yet reviewed',
                    ].join('\n')),
                    _cell(roomLabel(r.room)),
                    _cell(i.category.label),
                    _cell([i.brand, i.model, if (i.serial != null) 'S/N ${i.serial}']
                        .whereType<String>()
                        .join('\n')),
                    _cell('${i.qty}', align: pw.TextAlign.right),
                    _cell(range(lineLow(i), lineHigh(i)), align: pw.TextAlign.right),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    // 6. Photo appendix -------------------------------------------------------
    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        footer: footer,
        maxPages: 200,
        build: (context) => [
          pw.Header(level: 0, text: 'Photo appendix'),
          pw.Paragraph(
            text:
                'Originals are kept on the owner’s device; each carries a SHA-256 fingerprint recorded at capture time.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
          for (final r in data.rooms) ...[
            pw.Header(level: 1, text: roomLabel(r.room)),
            if (r.captures.isEmpty)
              pw.Paragraph(text: 'No photos.')
            else
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in r.captures)
                    pw.Container(
                      width: 160,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          images[c.id] != null
                              ? pw.Image(images[c.id]!, width: 160, height: 120, fit: pw.BoxFit.cover)
                              : pw.Container(
                                  width: 160,
                                  height: 120,
                                  color: PdfColors.grey300,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text('missing', style: const pw.TextStyle(fontSize: 8)),
                                ),
                          pw.Text(
                            [
                              dateTime.format(c.takenAt),
                              c.lat != null && c.lng != null
                                  ? '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}'
                                  : 'No location',
                              if (c.isCloseup) 'Close-up',
                              c.sha256.substring(0, 16),
                            ].join(' · '),
                            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );

    // 7. Disclaimer -----------------------------------------------------------
    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 0, text: 'Important notice'),
            pw.Paragraph(text: Disclaimer.short),
            pw.Paragraph(text: Disclaimer.aiDisclosure),
            pw.Paragraph(
              text:
                  'Estimated values are ranges for replacing each item with a new equivalent at the time of generation (${date.format(data.generatedAt)}). They are not market values, not depreciated values and not a professional appraisal. Verify quantities, descriptions and values before submitting this document to an insurer.',
            ),
            pw.Paragraph(
              text:
                  'Generated by HomeVault on ${dateTime.format(data.generatedAt)}. Item recognition was performed automatically from the owner’s photographs and reviewed by the owner.',
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _kv(String key, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          children: [
            pw.SizedBox(width: 200, child: pw.Text(key, style: const pw.TextStyle(color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ],
        ),
      );

  static pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      );
}
