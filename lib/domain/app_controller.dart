import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../data/local_store.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  final DataStore store;
  AppData data = AppData();
  String? _userId, _pendingUserId, demoOtp;
  DateTime? _otpExpires;
  int _otpAttempts = 0;
  bool _writing = false;
  AppController(this.store);
  Employee? get user =>
      data.employees.where((e) => e.id == _userId).firstOrNull;
  bool get isAdmin => user?.isAdmin ?? false;
  Future<void> load() async {
    data = await store.load();
    notifyListeners();
  }

  void requireAdmin() {
    if (!isAdmin) throw StateError('Chỉ quản trị viên được thực hiện.');
  }

  Employee requireUser() {
    final u = user;
    if (u == null || !u.active) throw StateError('Vui lòng đăng nhập lại.');
    return u;
  }

  Future<void> _commit(void Function(AppData) change) async {
    if (_writing) throw StateError('Đang lưu, vui lòng thử lại.');
    _writing = true;
    try {
      final next = AppData.fromJson(data.toJson());
      change(next);
      await store.save(next);
      data = next;
      notifyListeners();
    } finally {
      _writing = false;
    }
  }

  static String randomToken([int length = 24]) => base64UrlEncode(
    List.generate(length, (_) => Random.secure().nextInt(256)),
  );
  static Future<String> hashPassword(String password, String salt) async {
    final key =
        await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 100000,
          bits: 256,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(password)),
          nonce: utf8.encode(salt),
        );
    return base64Encode(await key.extractBytes());
  }

  void validateEmployee(Employee e, {bool editing = false}) {
    if (!['admin', 'employee'].contains(e.role)) {
      throw ArgumentError('Vai trò không hợp lệ.');
    }
    if (e.name.trim().isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_.-]{3,40}$').hasMatch(e.username)) {
      throw ArgumentError(
        'Nhập họ tên và tên đăng nhập 3–40 ký tự không dấu (chữ, số, _, ., -).',
      );
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e.email)) {
      throw ArgumentError('Email không hợp lệ.');
    }
    if (data.employees.any(
      (x) =>
          x.id != e.id &&
          (x.email.toLowerCase() == e.email.toLowerCase() ||
              x.username.toLowerCase() == e.username.toLowerCase()),
    )) {
      throw ArgumentError('Email hoặc tên đăng nhập đã tồn tại.');
    }
    if (e.shiftId != null && !data.shifts.any((s) => s.id == e.shiftId)) {
      throw ArgumentError('Ca làm không tồn tại.');
    }
  }

  Future<void> register(
    Employee employee,
    String password, {
    bool bootstrap = false,
  }) async {
    if (bootstrap && data.employees.isNotEmpty) {
      throw StateError('Đã có quản trị viên.');
    }
    if (!bootstrap && employee.isAdmin) {
      throw StateError('Không thể tự đăng ký admin.');
    }
    await saveEmployee(
      employee,
      password: password,
      bootstrap: bootstrap,
      selfRegister: !bootstrap,
    );
  }

  Future<void> saveEmployee(
    Employee employee, {
    String? password,
    bool bootstrap = false,
    bool selfRegister = false,
  }) async {
    if (!bootstrap && !selfRegister) requireAdmin();
    if (bootstrap && data.employees.isNotEmpty) {
      throw StateError('Đã có tài khoản.');
    }
    if (selfRegister &&
        (employee.isAdmin || data.employees.any((e) => e.id == employee.id))) {
      throw StateError('Đăng ký không hợp lệ.');
    }
    validateEmployee(employee);
    final existing = data.employees
        .where((e) => e.id == employee.id)
        .firstOrNull;
    if (existing?.id == _userId && (!employee.active || !employee.isAdmin)) {
      throw StateError('Không được khóa hoặc hạ quyền chính mình.');
    }
    if (password != null && password.isNotEmpty) {
      if (password.length < 8) {
        throw ArgumentError('Mật khẩu phải có ít nhất 8 ký tự.');
      }
      employee.salt = randomToken();
      employee.passwordHash = await hashPassword(password, employee.salt);
    } else if (existing == null) {
      throw ArgumentError('Cần mật khẩu cho tài khoản mới.');
    } else {
      employee.salt = existing.salt;
      employee.passwordHash = existing.passwordHash;
    }
    validateEmployee(employee);
    if (bootstrap && data.employees.isNotEmpty) {
      throw StateError('Đã có tài khoản.');
    }
    await _commit((d) {
      d.employees.removeWhere((e) => e.id == employee.id);
      d.employees.add(Employee.fromJson(employee.toJson()));
    });
  }

  Future<void> deleteEmployee(String id) async {
    requireAdmin();
    if (id == _userId) {
      throw StateError('Không thể xóa tài khoản đang đăng nhập.');
    }
    if (data.attendance.any((a) => a.employeeId == id) ||
        data.requests.any((r) => r.employeeId == id)) {
      throw StateError(
        'Nhân viên đã có lịch sử. Hãy khóa tài khoản để giữ dữ liệu.',
      );
    }
    await _commit((d) => d.employees.removeWhere((e) => e.id == id));
  }

  Future<void> beginLogin(String username, String password) async {
    _pendingUserId = null;
    demoOtp = null;
    final employee = data.employees
        .where((e) => e.username.toLowerCase() == username.trim().toLowerCase())
        .firstOrNull;
    if (employee == null ||
        !employee.active ||
        await hashPassword(password, employee.salt) != employee.passwordHash) {
      throw StateError(
        'Tên đăng nhập hoặc mật khẩu không đúng, hoặc tài khoản đã bị khóa.',
      );
    }
    _pendingUserId = employee.id;
    demoOtp = (100000 + Random.secure().nextInt(900000)).toString();
    _otpExpires = DateTime.now().add(const Duration(minutes: 2));
    _otpAttempts = 0;
  }

  void verifyOtp(String code) {
    if (_pendingUserId == null ||
        _otpExpires == null ||
        DateTime.now().isAfter(_otpExpires!) ||
        _otpAttempts >= 5) {
      _pendingUserId = null;
      demoOtp = null;
      throw StateError('OTP hết hạn hoặc vượt 5 lần thử. Hãy đăng nhập lại.');
    }
    _otpAttempts++;
    if (code.trim() != demoOtp) throw StateError('OTP không đúng.');
    _userId = _pendingUserId;
    _pendingUserId = null;
    demoOtp = null;
    notifyListeners();
  }

  void logout() {
    _userId = null;
    _pendingUserId = null;
    demoOtp = null;
    notifyListeners();
  }

  Future<void> saveShift(Shift shift) async {
    requireAdmin();
    if (shift.name.trim().isEmpty ||
        shift.startMinute < 0 ||
        shift.startMinute >= 1440 ||
        shift.endMinute < 0 ||
        shift.endMinute >= 1440 ||
        shift.startMinute == shift.endMinute ||
        shift.grace < 0 ||
        shift.grace > 60) {
      throw ArgumentError(
        'Ca phải có tên, giờ vào/ra khác nhau và dung sai từ 0–60 phút.',
      );
    }
    await _commit((d) {
      d.shifts.removeWhere((s) => s.id == shift.id);
      d.shifts.add(shift);
    });
  }

  Future<void> deleteShift(String id) async {
    requireAdmin();
    if (data.employees.any((e) => e.shiftId == id)) {
      throw StateError('Ca đang được phân công. Bỏ phân công trước khi xóa.');
    }
    await _commit((d) => d.shifts.removeWhere((s) => s.id == id));
  }

  Future<void> saveOffice(Office office) async {
    requireAdmin();
    if (office.name.trim().isEmpty ||
        office.latitude == null ||
        office.longitude == null ||
        !office.latitude!.isFinite ||
        !office.longitude!.isFinite ||
        office.latitude!.abs() > 90 ||
        office.longitude!.abs() > 180 ||
        !office.radius.isFinite ||
        office.radius < 20 ||
        office.radius > 5000) {
      throw ArgumentError('Nhập tọa độ hợp lệ và bán kính 20–5000 mét.');
    }
    if (office.qrSecret.isEmpty) office.qrSecret = randomToken();
    await _commit((d) => d.office = office);
  }

  String _qrFor(int slot) {
    final signature = crypto.Hmac(
      crypto.sha256,
      utf8.encode(data.office.qrSecret),
    ).convert(utf8.encode('baoan:$slot'));
    return 'BAOAN:$slot:$signature';
  }

  String officeQr(DateTime now) {
    requireAdmin();
    return _qrFor(now.millisecondsSinceEpoch ~/ 60000);
  }

  bool validQr(String code, DateTime now) {
    final slot = now.millisecondsSinceEpoch ~/ 60000;
    return code == _qrFor(slot) || code == _qrFor(slot - 1);
  }

  Attendance? get openAttendance => data.attendance
      .where((a) => a.employeeId == _userId && a.checkOut == null)
      .firstOrNull;
  Future<void> punch({
    required String qr,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double distance,
    required DateTime capturedAt,
    bool mocked = false,
  }) async {
    final u = requireUser();
    final now = DateTime.now();
    if (!data.office.configured) {
      throw StateError('Admin chưa cấu hình văn phòng.');
    }
    if (!validQr(qr, now)) {
      throw StateError('QR sai hoặc hết hạn. Quét mã mới từ Admin.');
    }
    if (mocked ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 80 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        now.difference(capturedAt).inSeconds > 60 ||
        capturedAt.isAfter(now.add(const Duration(seconds: 5)))) {
      throw StateError(
        'Vị trí không hợp lệ hoặc độ chính xác kém. Hãy lấy GPS mới, tắt vị trí giả.',
      );
    }
    // Recompute distance from coordinates. Never trust a distance supplied by UI.
    final rad = pi / 180;
    final h =
        pow(sin((latitude - data.office.latitude!) * rad / 2), 2) +
        cos(latitude * rad) *
            cos(data.office.latitude! * rad) *
            pow(sin((longitude - data.office.longitude!) * rad / 2), 2);
    final actualDistance = 6371000 * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)));
    if (actualDistance > data.office.radius) {
      throw StateError(
        'Bạn cách văn phòng ${actualDistance.round()} m, ngoài bán kính ${data.office.radius.round()} m.',
      );
    }
    final open = openAttendance;
    if (open != null) {
      if (now.isBefore(open.checkIn)) {
        throw StateError('Giờ thiết bị không hợp lệ.');
      }
      await _commit((d) {
        final a = d.attendance.firstWhere((a) => a.id == open.id);
        a.checkOut = now;
        a.outLatitude = latitude;
        a.outLongitude = longitude;
      });
      return;
    }
    final shift = data.shifts.where((s) => s.id == u.shiftId).firstOrNull;
    if (shift == null) {
      throw StateError('Bạn chưa được phân ca. Liên hệ Admin.');
    }
    // An overnight shift before its end belongs to the preceding workday.
    final anchor =
        shift.endMinute < shift.startMinute &&
            now.hour * 60 + now.minute < shift.endMinute
        ? now.subtract(const Duration(days: 1))
        : now;
    if (data.attendance.any(
      (a) =>
          a.employeeId == u.id &&
          dayKey(a.scheduledEnd) == dayKey(shift.endOn(anchor)),
    )) {
      throw StateError('Bạn đã hoàn tất ca của ngày này.');
    }
    if (data.requests.any(
      (r) =>
          r.employeeId == u.id &&
          r.type == 'Nghỉ phép' &&
          r.status == 'approved' &&
          dayKey(anchor).compareTo(dayKey(r.from)) >= 0 &&
          dayKey(anchor).compareTo(dayKey(r.to)) <= 0,
    )) {
      throw StateError(
        'Ngày này đã được duyệt nghỉ phép. Liên hệ Admin nếu lịch thay đổi.',
      );
    }
    final late = max(
      0,
      now.difference(shift.startOn(anchor)).inMinutes - shift.grace,
    );
    await _commit(
      (d) => d.attendance.add(
        Attendance(
          id: newId(),
          employeeId: u.id,
          shiftName: shift.name,
          checkIn: now,
          scheduledEnd: shift.endOn(anchor),
          lateMinutes: late,
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
        ),
      ),
    );
  }

  Future<void> saveRequest(WorkRequest r) async {
    final u = requireUser();
    if (r.employeeId != u.id) {
      throw StateError('Chỉ được tạo đơn của chính mình.');
    }
    final old = data.requests.where((e) => e.id == r.id).firstOrNull;
    if (old != null && (old.employeeId != u.id || old.status != 'pending')) {
      throw StateError('Chỉ được sửa đơn của mình đang chờ duyệt.');
    }
    if (r.status != 'pending' ||
        !['Nghỉ phép', 'Giải trình chấm công'].contains(r.type) ||
        r.reason.trim().length < 10 ||
        r.to.isBefore(r.from)) {
      throw ArgumentError(
        'Lý do ít nhất 10 ký tự, ngày kết thúc không trước ngày bắt đầu.',
      );
    }
    if (r.type == 'Nghỉ phép' &&
        data.requests.any(
          (e) =>
              e.id != r.id &&
              e.employeeId == u.id &&
              e.type == r.type &&
              e.status != 'rejected' &&
              !e.to.isBefore(r.from) &&
              !e.from.isAfter(r.to),
        )) {
      throw StateError('Khoảng ngày trùng với một đơn nghỉ phép hiện có.');
    }
    await _commit((d) {
      d.requests.removeWhere((e) => e.id == r.id);
      d.requests.add(r);
    });
  }

  Future<void> deleteRequest(String id) async {
    final u = requireUser();
    final r = data.requests.firstWhere((r) => r.id == id);
    if (r.employeeId != u.id || r.status != 'pending') {
      throw StateError('Chỉ được xóa đơn của mình đang chờ duyệt.');
    }
    await _commit((d) => d.requests.removeWhere((r) => r.id == id));
  }

  Future<void> reviewRequest(String id, bool approve, String note) async {
    requireAdmin();
    final r = data.requests.firstWhere((r) => r.id == id);
    if (r.employeeId == _userId || r.status != 'pending') {
      throw StateError('Không được duyệt đơn của mình hoặc đơn đã xử lý.');
    }
    if (note.trim().isEmpty) {
      throw ArgumentError('Nhập nhận xét khi duyệt hoặc từ chối.');
    }
    await _commit((d) {
      final r = d.requests.firstWhere((r) => r.id == id);
      r.status = approve ? 'approved' : 'rejected';
      r.reviewerNote = note.trim();
    });
  }
}
