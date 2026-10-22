import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../data/api_client.dart';
import '../data/api_repositories.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  final ApiClient client;
  final AuthService auth;
  final EmployeeRepository employeeRepo;
  final ShiftRepository shiftRepo;
  final OfficeRepository officeRepo;
  final AttendanceRepository attendanceRepo;
  final RequestRepository requestRepo;

  AppData data = AppData();
  Employee? _user;
  String? pendingChallengeId;
  String? pendingAction; // 'login' or 'register'
  String? pendingUsername;
  String? pendingEmail;
  String? demoOtp;
  String? currentServerQr;

  bool _loading = false;
  bool get isLoading => _loading;

  factory AppController([dynamic store]) => AppController.withServices();

  factory AppController.withServices({
    ApiClient? apiClient,
    AuthService? authService,
    EmployeeRepository? employeeRepository,
    ShiftRepository? shiftRepository,
    OfficeRepository? officeRepository,
    AttendanceRepository? attendanceRepository,
    RequestRepository? requestRepository,
  }) {
    final shared = apiClient ?? authService?.client ?? ApiClient();
    return AppController._(
      shared,
      authService ?? AuthService(shared),
      employeeRepository ?? EmployeeRepository(shared),
      shiftRepository ?? ShiftRepository(shared),
      officeRepository ?? OfficeRepository(shared),
      attendanceRepository ?? AttendanceRepository(shared),
      requestRepository ?? RequestRepository(shared),
    );
  }

  AppController._(
    this.client,
    this.auth,
    this.employeeRepo,
    this.shiftRepo,
    this.officeRepo,
    this.attendanceRepo,
    this.requestRepo,
  ) {
    client.onUnauthorized = () {
      _user = null;
      data = AppData();
      notifyListeners();
    };
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

  bool validQr(String code, DateTime now) {
    final slot = now.millisecondsSinceEpoch ~/ 60000;
    final secret = data.office.qrSecret;
    if (secret.isEmpty) return false;
    final sig = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('baoan:$slot'));
    final sigPrev = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('baoan:${slot - 1}'));
    return code == 'BAOAN:$slot:$sig' || code == 'BAOAN:${slot - 1}:$sigPrev';
  }

  factory AppController.createDefault() => AppController();

  Employee? get user => _user;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isManager => _user?.isManager ?? false;
  bool get isStaff => _user?.isStaff ?? false;

  Attendance? get openAttendance => data.attendance
      .where((a) => a.employeeId == _user?.id && a.checkOut == null)
      .firstOrNull;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      await client.init();
      _user = await auth.getMe();
      if (_user != null) {
        await syncAll();
      }
    } catch (_) {
      // Offline or network error
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void requireAdmin() {
    if (!isAdmin) throw StateError('Chỉ quản trị viên được thực hiện.');
  }

  void requireStaff() {
    if (!isStaff) throw StateError('Chỉ quản trị viên hoặc quản lý được thực hiện.');
  }

  Employee requireUser() {
    final u = _user;
    if (u == null || !u.active) throw StateError('Vui lòng đăng nhập lại.');
    return u;
  }

  Future<void> syncAll() async {
    try {
      final officeFuture = officeRepo.get().catchError((_) => data.office);
      final shiftsFuture = shiftRepo.list().catchError((_) => data.shifts);
      final attendanceFuture = attendanceRepo.list().catchError(
        (_) => data.attendance,
      );
      final requestsFuture = requestRepo.list().catchError(
        (_) => data.requests,
      );
      final employeesFuture = isStaff
          ? employeeRepo.list().catchError((_) => data.employees)
          : Future.value([?_user]);

      final results = await Future.wait([
        officeFuture,
        shiftsFuture,
        attendanceFuture,
        requestsFuture,
        employeesFuture,
      ]);

      data = AppData(
        office: results[0] as Office,
        shifts: results[1] as List<Shift>,
        attendance: results[2] as List<Attendance>,
        requests: results[3] as List<WorkRequest>,
        employees: results[4] as List<Employee>,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Lỗi đồng bộ dữ liệu: $e');
    }
  }

  // --- AUTHENTICATION ---

  Future<void> register(
    Employee employee,
    String password, {
    bool bootstrap = false,
  }) async {
    demoOtp = null;
    final cid = await auth.register(
      name: employee.name,
      email: employee.email,
      username: employee.username,
      password: password,
    );
    pendingChallengeId = cid;
    pendingAction = 'register';
    pendingEmail = employee.email;
    pendingUsername = employee.username;
    notifyListeners();
  }

  Future<void> verifyEmail(String code) async {
    if (pendingChallengeId == null) {
      throw StateError('Không có phiên xác minh email.');
    }
    await auth.verifyEmail(challengeId: pendingChallengeId!, code: code);
    pendingChallengeId = null;
    pendingAction = null;
    notifyListeners();
  }

  Future<void> beginLogin(String username, String password) async {
    demoOtp = null;
    final cid = await auth.login(username: username, password: password);
    pendingChallengeId = cid;
    pendingAction = 'login';
    pendingUsername = username;
    notifyListeners();
  }

  Future<void> verifyOtp(String code) async {
    if (pendingChallengeId == null) {
      throw StateError('Phiên OTP hết hạn hoặc không hợp lệ.');
    }
    _user = await auth.verifyOtp(challengeId: pendingChallengeId!, code: code);
    pendingChallengeId = null;
    pendingAction = null;
    pendingUsername = null;
    pendingEmail = null;
    demoOtp = null;
    await syncAll();
    notifyListeners();
  }

  /// Đăng nhập nhanh bằng sinh trắc học: bỏ qua mật khẩu + OTP.
  Future<void> loginWithRefreshToken(String refreshToken) async {
    _user = await auth.restoreSession(refreshToken);
    pendingChallengeId = null;
    pendingAction = null;
    await syncAll();
    notifyListeners();
  }

  Future<void> logout() async {
    await auth.logout();
    _user = null;
    data = AppData();
    pendingChallengeId = null;
    pendingAction = null;
    notifyListeners();
  }

  void cancelOtpStep() {
    pendingChallengeId = null;
    pendingAction = null;
    demoOtp = null;
    notifyListeners();
  }

  // --- CRUD EMPLOYEES (ADMIN) ---

  Future<void> saveEmployee(
    Employee employee, {
    String? password,
    bool bootstrap = false,
    bool selfRegister = false,
  }) async {
    if (selfRegister) {
      await register(employee, password ?? '');
      return;
    }
    requireAdmin();
    final existing = data.employees
        .where((e) => e.id == employee.id)
        .firstOrNull;
    if (existing != null) {
      final updated = await employeeRepo.update(
        id: employee.id,
        name: employee.name,
        email: employee.email,
        username: employee.username,
        department: employee.department,
        role: employee.role,
        active: employee.active,
        password: password,
      );
      if (employee.shiftId != existing.shiftId) {
        await employeeRepo.assignShift(employee.id, employee.shiftId);
      }
      final idx = data.employees.indexWhere((e) => e.id == employee.id);
      if (idx != -1) data.employees[idx] = updated;
    } else {
      final created = await employeeRepo.create(
        name: employee.name,
        email: employee.email,
        username: employee.username,
        password: password ?? '',
        department: employee.department,
        role: employee.role,
        shiftId: employee.shiftId,
      );
      data.employees.add(created);
    }
    await syncAll();
  }

  Future<void> deleteEmployee(String id) async {
    requireAdmin();
    if (id == _user?.id) {
      throw StateError('Không thể xóa tài khoản đang đăng nhập.');
    }
    await employeeRepo.delete(id);
    data.employees.removeWhere((e) => e.id == id);
    await syncAll();
  }

  // --- CRUD SHIFTS (ADMIN) ---

  Future<void> saveShift(Shift shift) async {
    requireAdmin();
    final existing = data.shifts.where((s) => s.id == shift.id).firstOrNull;
    if (existing != null) {
      final updated = await shiftRepo.update(shift);
      final idx = data.shifts.indexWhere((s) => s.id == shift.id);
      if (idx != -1) data.shifts[idx] = updated;
    } else {
      final created = await shiftRepo.create(shift);
      data.shifts.add(created);
    }
    await syncAll();
  }

  Future<void> deleteShift(String id) async {
    requireAdmin();
    await shiftRepo.delete(id);
    data.shifts.removeWhere((s) => s.id == id);
    await syncAll();
  }

  // --- OFFICE & QR (ADMIN & EMPLOYEE) ---

  Future<void> saveOffice(Office office) async {
    requireAdmin();
    final updated = await officeRepo.update(office);
    data.office = updated;
    notifyListeners();
  }

  Future<String> fetchServerQr() async {
    requireAdmin();
    final code = await officeRepo.createQr();
    currentServerQr = code;
    notifyListeners();
    return code;
  }

  String officeQr(DateTime now) {
    if (currentServerQr != null) return currentServerQr!;
    // Fallback if not fetched yet
    final slot = now.millisecondsSinceEpoch ~/ 60000;
    return 'BAOAN:$slot:server-signed';
  }

  // --- ATTENDANCE (EMPLOYEE PUNCH) ---

  Future<void> punch({
    required String qr,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double distance,
    required DateTime capturedAt,
    bool mocked = false,
  }) async {
    requireUser();
    final open = openAttendance;
    final idempotencyKey = '${newId()}_${capturedAt.millisecondsSinceEpoch}';

    if (open == null) {
      await attendanceRepo.checkIn(
        qr: qr,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        capturedAt: capturedAt,
        idempotencyKey: idempotencyKey,
        isMocked: mocked,
      );
    } else {
      await attendanceRepo.checkOut(
        qr: qr,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        capturedAt: capturedAt,
        idempotencyKey: idempotencyKey,
        isMocked: mocked,
      );
    }
    await syncAll();
  }

  // --- REQUESTS (LEAVE & EXPLANATION) ---

  Future<void> saveRequest(WorkRequest r) async {
    requireUser();
    final existing = data.requests.where((e) => e.id == r.id).firstOrNull;
    if (existing != null) {
      final updated = await requestRepo.update(r);
      final idx = data.requests.indexWhere((e) => e.id == r.id);
      if (idx != -1) data.requests[idx] = updated;
    } else {
      final created = await requestRepo.create(r);
      data.requests.insert(0, created);
    }
    await syncAll();
  }

  Future<void> deleteRequest(String id) async {
    requireUser();
    await requestRepo.delete(id);
    data.requests.removeWhere((r) => r.id == id);
    await syncAll();
  }

  Future<void> reviewRequest(String id, bool approve, String note) async {
    requireStaff();
    final req = data.requests.where((r) => r.id == id).firstOrNull;
    final updated = await requestRepo.review(
      id: id,
      approve: approve,
      note: note,
      version: req?.version,
    );
    final idx = data.requests.indexWhere((r) => r.id == id);
    if (idx != -1) data.requests[idx] = updated;
    await syncAll();
  }
}
