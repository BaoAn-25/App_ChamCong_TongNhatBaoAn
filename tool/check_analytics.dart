// Standalone regression runner; deliberately needs no Flutter/package resolution.
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import '../lib/domain/models.dart';
import '../lib/domain/attendance_analytics.dart';

Attendance row(
  String id,
  DateTime start, {
  String employee = 'a',
  DateTime? end,
  DateTime? scheduled,
  int late = 0,
}) => Attendance(
  id: id,
  employeeId: employee,
  shiftName: 'Ca',
  checkIn: start,
  scheduledEnd: scheduled ?? start.add(const Duration(hours: 8)),
  checkOut: end,
  lateMinutes: late,
  latitude: 0,
  longitude: 0,
  accuracy: 1,
);

void main() {
  var checks = 0;
  void check(bool ok, String name) {
    if (!ok) throw StateError(name);
    checks++;
    print('PASS $name');
  }

  final now = DateTime.utc(2026, 10, 31, 12);
  final lastDay = row(
    'last',
    DateTime.utc(2026, 10, 31, 1),
    end: DateTime.utc(2026, 10, 31, 9),
  );
  final active = row('active', DateTime.utc(2026, 10, 31, 11));
  final overdue = row('old', DateTime.utc(2026, 10, 30, 1));
  final future = row('future', DateTime.utc(2026, 11, 1));
  final stats = AttendanceAnalytics(
    [lastDay, active, overdue, future],
    now: now,
    monthly: true,
  );
  check(stats.records.length == 3, 'Exclude future dates');
  check(
    stats.buckets.length == 5 && stats.buckets.last.hours == 8,
    'Include days 29–31',
  );
  check(
    stats.overdue == 1 && stats.working == 1,
    'Active shift is not forgotten checkout',
  );
  check(stats.hours == 8 && stats.completed == 1, 'Count completed hours only');
  final empty = AttendanceAnalytics([], now: now, monthly: false);
  check(empty.onTimePercent == null, 'No invented perfect score without data');
  final scoped = AttendanceAnalytics(
    [lastDay],
    now: now,
    monthly: true,
    employeeId: 'b',
  );
  check(scoped.records.isEmpty, 'Employee data isolation');
  final boundary = row('timezone', DateTime.utc(2026, 9, 30, 18));
  check(
    AttendanceAnalytics([boundary], now: now, monthly: true).records.length ==
        1,
    'Vietnam month boundary',
  );
  final invalid = row(
    'invalid',
    now,
    end: now.subtract(const Duration(hours: 1)),
  );
  check(
    AttendanceAnalytics.safeHours(invalid) == 0,
    'Negative hours do not reduce totals',
  );
  final leap = AttendanceAnalytics(
    [],
    now: DateTime.utc(2024, 2, 29, 12),
    monthly: true,
  );
  check(leap.buckets.last.label == '29–29', 'Leap day included');
  final monday = DateTime.utc(2026, 10, 26, 2);
  check(
    AttendanceAnalytics(
          [
            row('sunday', monday.subtract(const Duration(days: 1))),
            row('monday', monday),
          ],
          now: monday,
          monthly: false,
        ).records.length ==
        1,
    'Week begins Monday',
  );
  print('$checks checks passed');
}
