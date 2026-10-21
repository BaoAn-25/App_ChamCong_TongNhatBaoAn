import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/app_controller.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/models.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/local_store.dart';

class TestStore implements DataStore {
  AppData data = AppData();
  bool fail = false;
  @override
  Future<AppData> load() async => AppData.fromJson(data.toJson());
  @override
  Future<void> save(AppData value) async {
    if (fail) throw StateError('Disk unavailable');
    data = AppData.fromJson(value.toJson());
  }
}

void main() {
  late AppController c;
  late TestStore store;
  late String hash;
  setUpAll(() async {
    hash = await AppController.hashPassword('Password123', 'test-salt');
  });
  setUp(() async {
    store = TestStore();
    store.data = AppData(
      employees: [
        Employee(
          id: 'admin',
          name: 'Admin',
          username: 'admin',
          email: 'admin@example.test',
          role: 'admin',
          salt: 'test-salt',
          passwordHash: hash,
        ),
        Employee(
          id: 'staff',
          name: 'Staff',
          username: 'staff',
          email: 'staff@example.test',
          salt: 'test-salt',
          passwordHash: hash,
          shiftId: 'day',
        ),
      ],
      shifts: [Shift(id: 'day', name: 'Day', startMinute: 0, endMinute: 1439)],
      office: Office(
        latitude: 10,
        longitude: 106,
        radius: 150,
        qrSecret: 'test-only',
      ),
    );
    c = AppController(store);
    await c.load();
  });
  Future<void> login(String name) async {
    c.logout();
    await c.beginLogin(name, 'Password123');
    c.verifyOtp(c.demoOtp!);
  }

  Future<void> punch(
    String qr, {
    double lat = 10,
    double accuracy = 5,
    bool mocked = false,
    DateTime? at,
  }) => c.punch(
    qr: qr,
    latitude: lat,
    longitude: 106,
    accuracy: accuracy,
    distance: 0,
    capturedAt: at ?? DateTime.now(),
    mocked: mocked,
  );

  test(
    'OTP required, consumed once, and limited to five failed attempts',
    () async {
      await c.beginLogin('staff', 'Password123');
      expect(c.user, isNull);
      final code = c.demoOtp!;
      c.verifyOtp(code);
      expect(c.user!.id, 'staff');
      expect(() => c.verifyOtp(code), throwsStateError);
      c.logout();
      await c.beginLogin('staff', 'Password123');
      for (var i = 0; i < 5; i++) {
        expect(() => c.verifyOtp('wrong'), throwsStateError);
      }
      expect(() => c.verifyOtp(c.demoOtp!), throwsStateError);
      expect(c.user, isNull);
    },
  );
  test('Wrong password does not start OTP', () async {
    await expectLater(c.beginLogin('staff', 'wrong'), throwsStateError);
    expect(c.demoOtp, isNull);
  });
  test('Employee cannot mutate shifts or office', () async {
    await login('staff');
    await expectLater(
      c.saveShift(Shift(id: 'x', name: 'X', startMinute: 10, endMinute: 20)),
      throwsStateError,
    );
    await expectLater(
      c.saveOffice(Office(latitude: 10, longitude: 106)),
      throwsStateError,
    );
  });
  test(
    'Registration cannot create admin or duplicate email ignoring case',
    () async {
      await expectLater(
        c.register(
          Employee(
            id: 'x',
            name: 'X',
            username: 'newuser',
            email: 'new@example.test',
            role: 'admin',
          ),
          'Password123',
        ),
        throwsStateError,
      );
      await expectLater(
        c.register(
          Employee(
            id: 'x',
            name: 'X',
            username: 'newuser',
            email: 'STAFF@example.test',
          ),
          'Password123',
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'Assigned shifts and employees with attendance cannot be deleted',
    () async {
      await login('admin');
      await expectLater(c.deleteShift('day'), throwsStateError);
      final qr = c.officeQr(DateTime.now());
      await login('staff');
      await punch(qr);
      await login('admin');
      await expectLater(c.deleteEmployee('staff'), throwsStateError);
    },
  );
  test('QR rejects old and altered payloads', () async {
    await login('admin');
    final now = DateTime.now();
    expect(c.validQr(c.officeQr(now), now), isTrue);
    expect(
      c.validQr(c.officeQr(now.subtract(const Duration(minutes: 3))), now),
      isFalse,
    );
    expect(c.validQr('${c.officeQr(now)}x', now), isFalse);
  });
  test(
    'GPS accuracy, freshness, mock and recomputed distance enforced',
    () async {
      await login('admin');
      final qr = c.officeQr(DateTime.now());
      await login('staff');
      await expectLater(punch(qr, lat: 11), throwsStateError);
      await expectLater(punch(qr, accuracy: 100), throwsStateError);
      await expectLater(punch(qr, mocked: true), throwsStateError);
      await expectLater(
        punch(qr, at: DateTime.now().subtract(const Duration(minutes: 2))),
        throwsStateError,
      );
      expect(c.data.attendance, isEmpty);
    },
  );
  test('Checkin, checkout and no second completed shift for the day', () async {
    await login('admin');
    final qr = c.officeQr(DateTime.now());
    await login('staff');
    await punch(qr);
    expect(c.openAttendance, isNotNull);
    await punch(qr);
    expect(c.openAttendance, isNull);
    expect(c.data.attendance.single.checkOut, isNotNull);
    await expectLater(punch(qr), throwsStateError);
    expect(c.data.attendance.length, 1);
  });
  test('Overnight shift end crosses midnight', () {
    final shift = Shift(
      id: 'night',
      name: 'Night',
      startMinute: 1320,
      endMinute: 360,
    );
    expect(shift.endOn(DateTime(2026, 10, 21)), DateTime(2026, 10, 22, 6));
  });
  test('Reviewed requests are immutable', () async {
    await login('staff');
    final r = WorkRequest(
      id: 'r',
      employeeId: 'staff',
      type: 'Nghỉ phép',
      reason: 'Family appointment',
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 2),
    );
    await c.saveRequest(r);
    await login('admin');
    await c.reviewRequest('r', true, 'Approved');
    await expectLater(c.reviewRequest('r', false, 'Changed'), throwsStateError);
    await login('staff');
    await expectLater(c.deleteRequest('r'), throwsStateError);
    await expectLater(c.saveRequest(r), throwsStateError);
  });
  test('Overlapping leave requests rejected', () async {
    await login('staff');
    WorkRequest request(String id) => WorkRequest(
      id: id,
      employeeId: 'staff',
      type: 'Nghỉ phép',
      reason: 'Family appointment',
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 2),
    );
    await c.saveRequest(request('r1'));
    await expectLater(c.saveRequest(request('r2')), throwsStateError);
  });
  test('Failed persistence does not leave phantom changes', () async {
    await login('admin');
    store.fail = true;
    await expectLater(
      c.saveShift(
        Shift(id: 'new', name: 'New', startMinute: 10, endMinute: 30),
      ),
      throwsStateError,
    );
    expect(c.data.shifts.length, 1);
  });
  test(
    'Persistence round-trip keeps attendance and office without session',
    () async {
      await login('admin');
      final qr = c.officeQr(DateTime.now());
      await login('staff');
      await punch(qr);
      final restored = AppController(store);
      await restored.load();
      expect(restored.data.attendance.single.employeeId, 'staff');
      expect(restored.data.office.latitude, 10);
      expect(restored.user, isNull);
    },
  );
}
