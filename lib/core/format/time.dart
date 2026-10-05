/// Times are shown in the restaurant's zone, Asia/Kolkata, whatever the phone's zone is.
///
/// India has one zone with a fixed offset (UTC+05:30) and no daylight saving, so a constant
/// offset is exact and avoids shipping the time-zone database.
const restaurantOffset = Duration(hours: 5, minutes: 30);

/// Parses an API instant (`2026-10-05T07:30:00.000Z`) as UTC.
DateTime parseInstant(String iso) => DateTime.parse(iso).toUtc();

DateTime? parseInstantOrNull(Object? value) => value is String ? parseInstant(value) : null;

/// The wall-clock time in Pune for [instant], as a UTC-flagged [DateTime] whose fields read as
/// local Pune time. Only use its fields for display.
DateTime toRestaurantTime(DateTime instant) => instant.toUtc().add(restaurantOffset);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "1:00 pm", "11:45 am": the website's style.
String formatTime(DateTime instant) {
  final t = toRestaurantTime(instant);
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${t.hour < 12 ? 'am' : 'pm'}';
}

/// "Wed, 7 Oct".
String formatShortDate(DateTime instant) {
  final t = toRestaurantTime(instant);
  return '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]}';
}

/// "Today", "Tomorrow" or "Wed, 7 Oct" for a restaurant-local `YYYY-MM-DD` date.
String formatDayLabel(String isoDate, {required DateTime now}) {
  final parts = isoDate.split('-').map(int.parse).toList();
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  final today = toRestaurantTime(now);
  final todayDate = DateTime.utc(today.year, today.month, today.day);
  final days = date.difference(todayDate).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
}

/// "Today, 1:00 pm", "Tomorrow, 12:30 pm" or "Wed, 7 Oct, 8:15 pm".
String formatDayAndTime(DateTime instant, {required DateTime now}) {
  final t = toRestaurantTime(instant);
  final iso =
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  return '${formatDayLabel(iso, now: now)}, ${formatTime(instant)}';
}

/// "just now", "5 min ago", "2 h ago", or the date and time.
String formatAgo(DateTime instant, {required DateTime now}) {
  final diff = now.difference(instant);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return formatDayAndTime(instant, now: now);
}

/// "in 12 min", "5 min late", "now": for kitchen due times.
String formatDueIn(DateTime due, {required DateTime now}) {
  final minutes = due.difference(now).inSeconds / 60;
  if (minutes >= 1) return 'in ${minutes.floor()} min';
  if (minutes > -1) return 'now';
  return '${(-minutes).floor()} min late';
}
