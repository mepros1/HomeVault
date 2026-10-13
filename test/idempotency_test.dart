import 'package:flutter_test/flutter_test.dart';
import 'package:homevault/data/api/idempotency.dart';

void main() {
  group('idempotencyKeyFor', () {
    test('is independent of capture order and hex case', () {
      final a = idempotencyKeyFor(['AAA', 'bbb', 'ccc']);
      final b = idempotencyKeyFor(['ccc', 'aaa', 'BBB']);
      expect(a, b);
      expect(a, hasLength(64));
    });

    test('changes when the set of captures changes', () {
      expect(
        idempotencyKeyFor(['aaa', 'bbb']),
        isNot(idempotencyKeyFor(['aaa', 'bbb', 'ccc'])),
      );
    });
  });
}
