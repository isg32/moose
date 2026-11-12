import 'package:intl/intl.dart';

/// Text formats from the design: 24 h times, `2h 24m`, `38:12`, `10d`,
/// "added 10 days ago", "FRIDAY 6 NOVEMBER", "Fri 20 Nov".
abstract final class VFormat {
  /// `2h 24m`, `45m`, `3h`.
  static String hm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// `2h 24m` from minutes.
  static String minutes(int minutes) => hm(Duration(minutes: minutes));

  /// `38:12` (minutes:seconds), or `1:02:05` past an hour.
  static String clock(Duration d) {
    final neg = d.isNegative;
    final a = d.abs();
    final h = a.inHours;
    final m = a.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = a.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = h > 0 ? '$h:$m:$s' : '${a.inMinutes}:$s';
    return neg ? '-$text' : text;
  }

  /// `07:00`.
  static String time(DateTime t) => DateFormat('HH:mm').format(t);

  /// "added today", "added 1 day ago", "added 10 days ago".
  static String added(int days) => switch (days) {
    <= 0 => 'added today',
    1 => 'added 1 day ago',
    _ => 'added $days days ago',
  };

  /// `10d`, or `0d` for today.
  static String ageShort(int days) => '${days}d';

  /// "10 days", "1 day", "Today".
  static String ageLong(int days) => switch (days) {
    <= 0 => 'Today',
    1 => '1 day',
    _ => '$days days',
  };

  /// `FRIDAY 6 NOVEMBER`.
  static String eyebrowDate(DateTime d) =>
      DateFormat('EEEE d MMMM').format(d).toUpperCase();

  /// `Fri 20 Nov`.
  static String shortDate(DateTime d) => DateFormat('EEE d MMM').format(d);

  /// `20 Nov`.
  static String dayMonth(DateTime d) => DateFormat('d MMM').format(d);

  /// `Tue 27 Oct, 09:14`.
  static String dateTime(DateTime d) =>
      DateFormat('EEE d MMM, HH:mm').format(d);

  /// `THURSDAY` or `TODAY`.
  static String dayHeading(DateTime d, DateTime now) {
    if (_sameDay(d, now)) return 'TODAY';
    return DateFormat('EEEE').format(d).toUpperCase();
  }

  /// Single-letter weekday: `M`, `T`, `W`, `T`, `F`, `S`, `S`.
  static String dayLetter(DateTime d) => 'MTWTFSS'[d.weekday - 1];

  /// `Sat`.
  static String dayAbbrev(DateTime d) => DateFormat('EEE').format(d);

  /// "Mon–Fri", "Sat, Sun", "Every day", "Weekdays".
  static String days(Set<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.isEmpty) return 'Never';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = days.toList()..sort();
    final contiguous = sorted.last - sorted.first + 1 == sorted.length;
    if (contiguous && sorted.length > 2) {
      return '${names[sorted.first - 1]}–${names[sorted.last - 1]}';
    }
    return sorted.map((d) => names[d - 1]).join(', ');
  }

  /// "weekdays", "weekends", "every day", else "Mon, Wed".
  static String daysWord(Set<int> d) {
    if (d.length == 7) return 'every day';
    if (d.length == 5 && d.containsAll(const {1, 2, 3, 4, 5})) {
      return 'weekdays';
    }
    if (d.length == 2 && d.containsAll(const {6, 7})) return 'weekends';
    return days(d);
  }

  /// "1 app", "4 apps".
  static String count(int n, String singular, [String? plural]) =>
      '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

  /// "Good morning", "Good afternoon", "Good evening".
  static String greeting(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// `0:42`.
  static String length(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
