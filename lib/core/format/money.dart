/// Money is whole paise in integers, never floating-point rupees.
///
/// Formatting follows `en-IN`, as the website does: Indian digit grouping (₹1,23,456),
/// and no paise when there are none (₹280 rather than ₹280.00), which reads better on a menu.
String formatPaise(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final rest = abs % 100;
  final whole = _groupIndian(rupees);
  final text = rest == 0 ? '₹$whole' : '₹$whole.${rest.toString().padLeft(2, '0')}';
  return negative ? '−$text' : text;
}

/// 1234567 -> "12,34,567": the last three digits, then pairs.
String _groupIndian(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final pairs = <String>[];
  while (head.length > 2) {
    pairs.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) pairs.insert(0, head);
  return '${pairs.join(',')},$last3';
}

/// `amount × basisPoints / 10 000`, rounded half up, as the server computes GST.
int percentOf(int amountPaise, int basisPoints) => (amountPaise * basisPoints + 5000) ~/ 10000;

/// "5%" from 500 basis points, "2.5%" from 250.
String formatBasisPoints(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final frac = basisPoints % 100;
  if (frac == 0) return '$whole%';
  final f = frac % 10 == 0 ? (frac ~/ 10).toString() : frac.toString().padLeft(2, '0');
  return '$whole.$f%';
}
