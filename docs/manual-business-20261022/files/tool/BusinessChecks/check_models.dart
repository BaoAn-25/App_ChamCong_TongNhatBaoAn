import '../../lib/domain/models.dart';

void main() {
  var passed = 0;
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
    passed++;
    print('PASS $name');
  }
  final instant = parseApiInstant('2026-10-22T05:50:00Z');
  check(instant.toUtc() == DateTime.utc(2026, 10, 22, 5, 50), 'UTC instant preserved');
  check(parseApiInstant('2026-10-22T12:50:00+07:00') == instant, 'Offset preserved');
  try {
    parseApiInstant('2026-10-22T05:50:00');
    throw StateError('Accepted ambiguous instant');
  } on FormatException {
    check(true, 'Reject missing timezone');
  }
  final json = <String, dynamic>{
    'id': 'a', 'employeeId': 'e', 'shiftName': 'Ca ngày',
    'checkIn': '2026-10-22T01:00:00Z', 'scheduledStart': '2026-10-22T01:00:00Z',
    'scheduledEnd': '2026-10-22T10:00:00Z', 'checkOut': '2026-10-22T10:00:00Z',
    'lateMinutes': 0, 'latitude': 10, 'longitude': 106, 'accuracy': 20,
    'netMinutes': 480, 'breakMinutes': 60, 'expectedMinutes': 480, 'status': 'DungGio',
  };
  final row = Attendance.fromJson(json);
  check(row.hours == 8, 'Uses server net minutes');
  check(row.toJson()['checkIn'].toString().endsWith('Z'), 'Cache UTC Z');
  check(Attendance.fromJson(row.toJson()).hours == 8, 'Cache round trip');
  check(Attendance.fromJson({...json, 'isAutoClosed': true, 'status': 'QuenCheckOut'}).hours == 0, 'Forgot checkout zero hours');
  check(Attendance.fromJson({...json, 'status': 'DiTre, BatThuong'}).hours == 0, 'Abnormal zero hours');
  check(Attendance.fromJson({...json, 'checkOut': null}).hours == 0, 'Open zero hours');
  check(Attendance.fromJson({...json, 'earlyLeaveMinutes': 12}).explanation.contains('12'), 'Server early minutes');
  check(Employee.fromJson({'id':'e','approvalStatus':'PendingApproval'}).approvalStatus == 'PendingApproval', 'Approval parsed');
  check(Shift.fromJson({'breakMinutes':60,'earlyLeaveGraceMinutes':5}).breakMinutes == 60, 'Break parsed');
  check(Office().radius == 100, 'Default radius 100');
  final request = WorkRequest.fromJson({
    'id':'r','employeeId':'e','from':'2026-10-23','to':'2026-10-26', 'days':2,
    'reviewedBy':'admin','reviewerName':'Admin','reviewedAt':'2026-10-22T05:50:00Z',
  });
  check(request.days == 2 && request.reviewedAt == instant, 'Review metadata parsed');
  check(request.from.day == 23 && request.to.day == 26, 'DateOnly never timezone shifted');
  print('$passed Dart checks passed.');
}
