import '../domain/models.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient client;
  AuthService(this.client);

  Future<String> register({
    required String name,
    required String email,
    required String username,
    required String password,
  }) async {
    final res = await client.post(
      '/api/auth/register',
      auth: false,
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
      },
    );
    return res['challengeId'].toString();
  }

  Future<void> verifyEmail({
    required String challengeId,
    required String code,
  }) async {
    await client.post(
      '/api/auth/verify-email',
      auth: false,
      body: {
        'challengeId': challengeId,
        'code': code.trim(),
      },
    );
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final res = await client.post(
      '/api/auth/login',
      auth: false,
      body: {
        'username': username.trim(),
        'password': password,
      },
    );
    return res['challengeId'].toString();
  }

  Future<Employee> verifyOtp({
    required String challengeId,
    required String code,
  }) async {
    final res = await client.post(
      '/api/auth/verify-otp',
      auth: false,
      body: {
        'challengeId': challengeId,
        'code': code.trim(),
      },
    );
    await client.setTokens(
      access: res['accessToken'],
      refresh: res['refreshToken'],
    );
    return Employee.fromJson(res['user']);
  }

  Future<void> logout() async {
    try {
      await client.post('/api/auth/logout', body: {});
    } catch (_) {}
    await client.clearTokens();
  }

  Future<Employee?> getMe() async {
    if (!client.hasTokens) return null;
    try {
      final res = await client.get('/api/me');
      return Employee.fromJson(res);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }
}

class EmployeeRepository {
  final ApiClient client;
  EmployeeRepository(this.client);

  Future<List<Employee>> list() async {
    final res = await client.get('/api/employees') as List;
    return res.map((j) => Employee.fromJson(j)).toList();
  }

  Future<Employee> create({
    required String name,
    required String email,
    required String username,
    required String password,
    String? department,
    String? role,
    String? shiftId,
  }) async {
    final res = await client.post(
      '/api/employees',
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
        'department': department?.trim(),
        'role': role ?? 'employee',
        'shiftId': shiftId,
      },
    );
    return Employee.fromJson(res);
  }

  Future<Employee> update({
    required String id,
    String? name,
    String? email,
    String? username,
    String? password,
    String? department,
    String? role,
    bool? active,
  }) async {
    final res = await client.patch(
      '/api/employees/$id',
      body: {
        if (name != null) 'name': name.trim(),
        if (email != null) 'email': email.trim(),
        if (username != null) 'username': username.trim(),
        if (password != null && password.isNotEmpty) 'password': password,
        if (department != null) 'department': department.trim(),
        'role': ?role,
        'active': ?active,
      },
    );
    return Employee.fromJson(res);
  }

  Future<void> delete(String id) async {
    await client.delete('/api/employees/$id');
  }

  Future<Employee> assignShift(String employeeId, String? shiftId) async {
    final res = await client.put(
      '/api/employees/$employeeId/shift',
      body: {'shiftId': shiftId},
    );
    return Employee.fromJson(res);
  }
}

class ShiftRepository {
  final ApiClient client;
  ShiftRepository(this.client);

  Future<List<Shift>> list() async {
    final res = await client.get('/api/shifts') as List;
    return res.map((j) => Shift.fromJson(j)).toList();
  }

  Future<Shift> create(Shift s) async {
    final res = await client.post(
      '/api/shifts',
      body: {
        'name': s.name.trim(),
        'startMinute': s.startMinute,
        'endMinute': s.endMinute,
        'grace': s.grace,
      },
    );
    return Shift.fromJson(res);
  }

  Future<Shift> update(Shift s) async {
    final res = await client.patch(
      '/api/shifts/${s.id}',
      body: {
        'name': s.name.trim(),
        'startMinute': s.startMinute,
        'endMinute': s.endMinute,
        'grace': s.grace,
      },
    );
    return Shift.fromJson(res);
  }

  Future<void> delete(String id) async {
    await client.delete('/api/shifts/$id');
  }
}

class OfficeRepository {
  final ApiClient client;
  OfficeRepository(this.client);

  Future<Office> get() async {
    final res = await client.get('/api/office');
    return Office.fromJson(res);
  }

  Future<Office> update(Office o) async {
    final res = await client.put(
      '/api/office',
      body: {
        'name': o.name.trim(),
        'latitude': o.latitude,
        'longitude': o.longitude,
        'radius': o.radius,
      },
    );
    return Office.fromJson(res);
  }

  Future<String> createQr() async {
    final res = await client.post('/api/office/qr');
    return res['code'] as String;
  }
}

class AttendanceRepository {
  final ApiClient client;
  AttendanceRepository(this.client);

  Future<Attendance> checkIn({
    required String qr,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime capturedAt,
    required String idempotencyKey,
    bool isMocked = false,
  }) async {
    final res = await client.post(
      '/api/attendance/check-in',
      body: {
        'qr': qr.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'idempotencyKey': idempotencyKey,
        'isMocked': isMocked,
      },
    );
    return Attendance.fromJson(res);
  }

  Future<Attendance> checkOut({
    required String qr,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime capturedAt,
    required String idempotencyKey,
    bool isMocked = false,
  }) async {
    final res = await client.post(
      '/api/attendance/check-out',
      body: {
        'qr': qr.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'idempotencyKey': idempotencyKey,
        'isMocked': isMocked,
      },
    );
    return Attendance.fromJson(res);
  }

  Future<List<Attendance>> list({
    DateTime? from,
    DateTime? to,
    String? employeeId,
    int page = 1,
    int pageSize = 100,
  }) async {
    final query = <String, dynamic>{
      if (from != null) 'from': dayKey(from),
      if (to != null) 'to': dayKey(to),
      'employeeId': ?employeeId,
      'page': page,
      'pageSize': pageSize,
    };
    final res = await client.get('/api/attendance', query: query);
    final items = (res['items'] as List?) ?? [];
    return items.map((j) => Attendance.fromJson(j)).toList();
  }
}

class RequestRepository {
  final ApiClient client;
  RequestRepository(this.client);

  Future<List<WorkRequest>> list({String? status}) async {
    final query = status != null ? {'status': status} : null;
    final res = await client.get('/api/requests', query: query) as List;
    return res.map((j) => WorkRequest.fromJson(j)).toList();
  }

  Future<WorkRequest> create(WorkRequest r) async {
    final res = await client.post(
      '/api/requests',
      body: {
        'type': r.type,
        'reason': r.reason.trim(),
        'from': dayKey(r.from),
        'to': dayKey(r.to),
      },
    );
    return WorkRequest.fromJson(res);
  }

  Future<WorkRequest> update(WorkRequest r) async {
    final res = await client.patch(
      '/api/requests/${r.id}',
      body: {
        'type': r.type,
        'reason': r.reason.trim(),
        'from': dayKey(r.from),
        'to': dayKey(r.to),
      },
    );
    return WorkRequest.fromJson(res);
  }

  Future<void> delete(String id) async {
    await client.delete('/api/requests/$id');
  }

  Future<WorkRequest> review({
    required String id,
    required bool approve,
    required String note,
    int? version,
  }) async {
    final res = await client.post(
      '/api/requests/$id/review',
      body: {
        'approve': approve,
        'note': note.trim(),
        'version': version,
      },
    );
    return WorkRequest.fromJson(res);
  }
}
