import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/models.dart';

void main() {
  test(
    'Overnight shifts preserve calendar boundaries including year rollover',
    () {
      final shift = Shift(
        id: 'n',
        name: 'Night',
        startMinute: 1320,
        endMinute: 360,
      );
      expect(shift.startOn(DateTime(2026, 12, 31)), DateTime(2026, 12, 31, 22));
      expect(shift.endOn(DateTime(2026, 12, 31)), DateTime(2027, 1, 1, 6));
    },
  );
  test('Normal shift ends on same workday', () {
    final shift = Shift(
      id: 'd',
      name: 'Day',
      startMinute: 480,
      endMinute: 1020,
    );
    expect(shift.endOn(DateTime(2026, 10, 21)), DateTime(2026, 10, 21, 17));
  });
  test(
    'Full snapshot round-trip preserves links, flags and checkout location',
    () {
      final data = AppData(
        employees: [
          Employee(
            id: 'e',
            name: 'An',
            email: 'an@example.test',
            username: 'baoan',
            shiftId: 's',
            active: false,
          ),
        ],
        shifts: [
          Shift(id: 's', name: 'Ca ngày', startMinute: 480, endMinute: 1020),
        ],
        attendance: [
          Attendance(
            id: 'a',
            employeeId: 'e',
            shiftName: 'Ca ngày',
            checkIn: DateTime(2026, 10, 21, 8),
            scheduledEnd: DateTime(2026, 10, 21, 17),
            lateMinutes: 0,
            latitude: 10.5,
            longitude: 106.5,
            accuracy: 5,
            checkOut: DateTime(2026, 10, 21, 17),
            outLatitude: 10.6,
            outLongitude: 106.6,
          ),
        ],
        requests: [
          WorkRequest(
            id: 'r',
            employeeId: 'e',
            type: 'Nghỉ phép',
            reason: 'Việc gia đình',
            from: DateTime(2026, 10, 22),
            to: DateTime(2026, 10, 22),
          ),
        ],
        office: Office(latitude: 10.5, longitude: 106.5, qrSecret: 'test'),
      );
      final restored = AppData.fromJson(data.toJson());
      expect(restored.toJson(), data.toJson());
      expect(restored.attendance.single.hours, 9);
      expect(restored.employees.single.active, isFalse);
      expect(restored.office.configured, isTrue);
    },
  );
  test('Unknown storage version fails rather than erasing data', () {
    expect(() => AppData.fromJson({'version': 99}), throwsFormatException);
  });
  test('Open attendance after shift explains missing checkout', () {
    final old = DateTime.now().subtract(const Duration(days: 2));
    final a = Attendance(
      id: 'a',
      employeeId: 'e',
      shiftName: 'Day',
      checkIn: old,
      scheduledEnd: old.add(const Duration(hours: 8)),
      lateMinutes: 15,
      latitude: 10,
      longitude: 106,
      accuracy: 5,
    );
    expect(a.explanation, contains('Đi trễ 15 phút'));
    expect(a.explanation, contains('chưa ghi nhận giờ ra'));
    expect(a.hours, 0);
  });
  test('Early checkout explanation and fractional hours', () {
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
    expect(a.explanation, contains('Ra sớm 30 phút'));
    expect(a.hours, 8.5);
  });
}
