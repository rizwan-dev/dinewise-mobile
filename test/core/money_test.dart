import 'package:dinewise/core/format/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPaise', () {
    test('drops the paise when there are none, as menu prices read', () {
      expect(formatPaise(28000), '₹280');
      expect(formatPaise(0), '₹0');
      expect(formatPaise(100), '₹1');
    });

    test('shows two decimals when there are paise', () {
      expect(formatPaise(80850), '₹808.50');
      expect(formatPaise(5), '₹0.05');
      expect(formatPaise(12345), '₹123.45');
    });

    test('groups digits the Indian way', () {
      expect(formatPaise(100000), '₹1,000');
      expect(formatPaise(12345600), '₹1,23,456');
      expect(formatPaise(1234567800), '₹1,23,45,678');
      expect(formatPaise(99999999), '₹9,99,999.99');
    });

    test('marks negative amounts with a minus sign', () {
      expect(formatPaise(-5000), '−₹50');
    });
  });

  group('percentOf', () {
    test('rounds half up to the paisa, as the server computes GST', () {
      // 5% of ₹770.00 = ₹38.50.
      expect(percentOf(77000, 500), 3850);
      // 5% of 30 paise = 1.5 -> 2.
      expect(percentOf(30, 500), 2);
      // 5% of 29 paise = 1.45 -> 1.
      expect(percentOf(29, 500), 1);
    });
  });

  test('formatBasisPoints', () {
    expect(formatBasisPoints(500), '5%');
    expect(formatBasisPoints(250), '2.5%');
    expect(formatBasisPoints(1805), '18.05%');
  });
}
