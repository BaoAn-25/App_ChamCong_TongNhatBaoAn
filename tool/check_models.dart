// Dependency-free checks for environments that cannot run Flutter's socket-based
// test runner. Run: dart tool/check_models.dart
// Direct import and console output intentionally allow execution before pub get.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import '../lib/domain/models.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError('FAIL: $label');
  print('PASS: $label');
}

void main() {
  final night = Shift(
    id: 'night',
    name: 'Night',
    startMinute: 1320,
    endMinute: 360,
  );
  check(
    night.endOn(DateTime(2026, 12, 31)) == DateTime(2027, 1, 1, 6),
    'Overnight shift crosses year boundary',
  );
  final day = Shift(id: 'day', name: 'Day', startMinute: 480, endMinute: 1020);
  check(
    day.endOn(DateTime(2026, 10, 21)) == DateTime(2026, 10, 21, 17),
    'Day shift ends on same date',
  );
  final a = Attendance(
    id: 'a',
    employeeId: 'e',
    shiftName: 'Day',
    checkIn: DateTime(2026, 10, 21, 8),
    scheduledEnd: DateTime(2026, 10, 21, 17),
    lateMinutes: 0,
    latitude: 10,
    longitude: 106,
    accuracy: 5,
    checkOut: DateTime(2026, 10, 21, 16, 30),
  );
  check(
    a.hours == 8.5 && a.explanation.contains('30'),
    'Fractional hours and early checkout explanation',
  );
  final old = DateTime.now().subtract(const Duration(days: 2));
  final open = Attendance(
    id: 'b',
    employeeId: 'e',
    shiftName: 'Day',
    checkIn: old,
    scheduledEnd: old.add(const Duration(hours: 8)),
    lateMinutes: 15,
    latitude: 10,
    longitude: 106,
    accuracy: 5,
  );
  check(
    open.hours == 0 &&
        open.explanation.contains('15') &&
        open.explanation.contains('chưa ghi nhận giờ ra'),
    'Missing checkout and lateness explanation',
  );
  final data = AppData(
    employees: [
      Employee(
        id: 'e',
        name: 'An',
        email: 'an@example.test',
        username: 'baoan',
        shiftId: 'day',
        active: false,
      ),
    ],
    shifts: [day],
    attendance: [a, open],
    office: Office(latitude: 10, longitude: 106, qrSecret: 'test'),
    requests: [
      WorkRequest(
        id: 'r',
        employeeId: 'e',
        type: 'Nghỉ phép',
        reason: 'Việc gia đình',
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 2),
      ),
    ],
  );
  final raw = jsonEncode(data.toJson());
  check(
    jsonEncode(AppData.fromJson(jsonDecode(raw)).toJson()) == raw,
    'Complete persistent snapshot round-trip',
  );
  var rejected = false;
  try {
    AppData.fromJson({'version': 99});
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'Unknown data version rejected');
}
