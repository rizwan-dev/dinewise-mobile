import 'package:dinewise/core/format/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 12:23 pm in Pune.
  final now = DateTime.utc(2026, 10, 5, 6, 53);

  test('parses API instants as UTC', () {
    final t = parseInstant('2026-10-05T07:30:00.000Z');
    expect(t.isUtc, isTrue);
    expect(t, DateTime.utc(2026, 10, 5, 7, 30));
    expect(parseInstantOrNull(null), isNull);
  });

  test('shows times in Asia/Kolkata whatever the phone zone is', () {
    expect(formatTime(DateTime.utc(2026, 10, 5, 7, 30)), '1:00 pm');
    expect(formatTime(DateTime.utc(2026, 10, 5, 6, 15)), '11:45 am');
    expect(formatTime(DateTime.utc(2026, 10, 5, 18, 30)), '12:00 am');
    expect(formatTime(DateTime.utc(2026, 10, 5, 6, 30)), '12:00 pm');
  });

  test('crosses midnight in Pune before UTC does', () {
    // 19:00 UTC on the 5th is 00:30 on the 6th in Pune.
    expect(formatShortDate(DateTime.utc(2026, 10, 5, 19)), 'Tue, 6 Oct');
  });

  test('labels slot days relative to today in Pune', () {
    expect(formatDayLabel('2026-10-05', now: now), 'Today');
    expect(formatDayLabel('2026-10-06', now: now), 'Tomorrow');
    expect(formatDayLabel('2026-10-07', now: now), 'Wed, 7 Oct');
    // Late evening UTC on the 4th is already the 5th in Pune.
    expect(formatDayLabel('2026-10-05', now: DateTime.utc(2026, 10, 4, 19)), 'Today');
  });

  test('formatDayAndTime', () {
    expect(formatDayAndTime(DateTime.utc(2026, 10, 6, 7), now: now), 'Tomorrow, 12:30 pm');
  });

  test('formatDueIn counts down and then up', () {
    final due = DateTime.utc(2026, 10, 5, 7);
    expect(formatDueIn(due, now: DateTime.utc(2026, 10, 5, 6, 48)), 'in 12 min');
    expect(formatDueIn(due, now: DateTime.utc(2026, 10, 5, 7, 0, 20)), 'now');
    expect(formatDueIn(due, now: DateTime.utc(2026, 10, 5, 7, 8)), '8 min late');
  });

  test('formatAgo', () {
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(formatAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(formatAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
  });
}
