import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/ocr/label_parser.dart';

void main() {
  test('labelled serial and model come first', () {
    final info = LabelParser.parse('''
Samsung Electronics
MODEL: RF28T5001SR
S/N: 0B4G4BCT200123X
Made in Mexico  120V 60Hz
''');
    expect(info.serials.first, '0B4G4BCT200123X');
    expect(info.models.first, 'RF28T5001SR');
  });

  test('variants: "Serial No.", "SN", "Model No"', () {
    expect(LabelParser.parse('Serial No. AB12345678').serials.first, 'AB12345678');
    expect(LabelParser.parse('SN 7788-9900-A').serials.first, '7788-9900-A');
    expect(LabelParser.parse('Model No: WM3900HWA').models.first, 'WM3900HWA');
    expect(LabelParser.parse('M/N: LG-42LN5400').models.first, 'LG-42LN5400');
  });

  test('falls back to bare alphanumeric tokens, longest first', () {
    final info = LabelParser.parse('KitchenAid KSM150PSER 1234567890 MADE IN CHINA 120V');
    expect(info.serials, ['KSM150PSER', '1234567890']);
    expect(info.models, isEmpty);
  });

  test('ignores label words, short numbers and units', () {
    final info = LabelParser.parse('WARNING 120V 60Hz 2024 MODEL CHINA');
    expect(info.isEmpty, isTrue);
  });

  test('empty OCR gives empty info', () {
    expect(LabelParser.parse('').isEmpty, isTrue);
  });
}
