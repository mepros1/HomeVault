import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/core/enums.dart';
import 'package:homevault/data/api/analyze_room_models.dart';

/// The sample response from spec §5.1, verbatim.
const _specSample = '''
{
  "request_id": "req_01J...",
  "model": "gemini-3.1-flash-lite",
  "items": [
    {
      "name": "Flat-screen television",
      "category": "Electronics",
      "brand": "Samsung",
      "model": null,
      "serial": null,
      "qty": 1,
      "condition": "good",
      "est_low": 400,
      "est_high": 900,
      "currency": "USD",
      "confidence": 0.86,
      "source_image_index": 0,
      "note": "Wall-mounted, approx. 55 inch"
    }
  ],
  "usage": { "input_tokens": 6480, "output_tokens": 1520 },
  "warnings": []
}
''';

void main() {
  test('parses the spec sample response', () {
    final response = AnalyzeRoomResponse.fromJson(
      jsonDecode(_specSample) as Map<String, dynamic>,
    );
    expect(response.requestId, 'req_01J...');
    expect(response.items, hasLength(1));
    final tv = response.items.single;
    expect(tv.category, ItemCategory.electronics);
    expect(tv.condition, ItemCondition.good);
    expect(tv.brand, 'Samsung');
    expect(tv.model, isNull);
    expect(tv.estLow, 400);
    expect(tv.estHigh, 900);
    expect(tv.confidence, closeTo(0.86, 1e-9));
    expect(response.usage.inputTokens, 6480);
    expect(response.warnings, isEmpty);
    expect(response.promptVersion, isNull);
  });

  test('unknown category falls back to Other, unknown condition to null', () {
    final item = AnalyzedItem.fromJson({
      'name': 'Thing',
      'category': 'Spaceships',
      'condition': 'mint',
      'est_low': 1,
      'est_high': 2,
      'confidence': 0.5,
      'source_image_index': 0,
    });
    expect(item.category, ItemCategory.other);
    expect(item.condition, isNull);
    expect(item.qty, 1);
    expect(item.currency, 'USD');
  });

  test('condition "new" maps to brandNew', () {
    final item = AnalyzedItem.fromJson({
      'name': 'Box',
      'category': 'Other',
      'condition': 'new',
      'est_low': 1,
      'est_high': 2,
      'confidence': 0.9,
      'source_image_index': 1,
    });
    expect(item.condition, ItemCondition.brandNew);
    expect(item.toJson()['condition'], 'new');
  });
}
