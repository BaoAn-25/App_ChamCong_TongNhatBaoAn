import 'dart:math';

typedef Json = Map<String, dynamic>;

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String clock(DateTime? d) => d == null
    ? '—'
    : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String dateLabel(DateTime d) => '${d.day}/${d.month}/${d.year}';

class Employee {
  final String id;
  String name, email, username, department, role, passwordHash, salt;
  String? shiftId;
  bool active;

  Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    this.department = '',
    this.role = 'employee',
    this.passwordHash = '',
    this.salt = '',
    this.shiftId,
    this.active = true,
  });

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isStaff => isAdmin || isManager;

  Json toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'username': username,
    'department': department,
    'role': role,
    'passwordHash': passwordHash,
    'salt': salt,
    'shiftId': shiftId,
    'active': active,
  };

  factory Employee.fromJson(Json j) => Employee(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    email: j['email']?.toString() ?? '',
    username: j['username']?.toString() ?? '',
    department: j['department']?.toString() ?? '',
    role: j['role']?.toString() ?? 'employee',
    passwordHash: j['passwordHash']?.toString() ?? '',
    salt: j['salt']?.toString() ?? '',
    shiftId: j['shiftId']?.toString(),
    active: j['active'] as bool? ?? true,
  );
}

class Department {
  final String id;
  String name;
  String? description;

  Department({
    required this.id,
    required this.name,
    this.description,
  });

  Json toJson() => {
    'id': id,
    'name': name,
    'description': description,
  };

  factory Department.fromJson(Json j) => Department(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
  );
}

class Shift {
  final String id;
  String name;
  int startMinute, endMinute, grace;

  Shift({
    required this.id,
    required this.name,
    required this.startMinute,
    required this.endMinute,
    this.grace = 5,
  });

  DateTime startOn(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(Duration(minutes: startMinute));

  DateTime endOn(DateTime d) => DateTime(
    d.year,
    d.month,
    d.day,
  ).add(Duration(minutes: endMinute + (endMinute <= startMinute ? 1440 : 0)));

  Json toJson() => {
    'id': id,
    'name': name,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'grace': grace,
  };

  factory Shift.fromJson(Json j) => Shift(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    startMinute: (j['startMinute'] ?? j['start'] ?? 0) as int,
    endMinute: (j['endMinute'] ?? j['end'] ?? 0) as int,
    grace: (j['grace'] ?? 5) as int,
  );
}

class Attendance {
  final String id, employeeId, shiftName;
  final DateTime checkIn, scheduledEnd;
  final int lateMinutes;
  final double latitude, longitude, accuracy;
  DateTime? checkOut;
  double? outLatitude, outLongitude;
  String? employeeName;

  Attendance({
    required this.id,
    required this.employeeId,
    required this.shiftName,
    required this.checkIn,
    required this.scheduledEnd,
    required this.lateMinutes,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.checkOut,
    this.outLatitude,
    this.outLongitude,
    this.employeeName,
  });

  String get explanation {
    final items = <String>[];
    if (lateMinutes > 0) {
      items.add('Đi trễ $lateMinutes phút (đã trừ thời gian cho phép).');
    }
    if (checkOut == null && DateTime.now().isAfter(scheduledEnd)) {
      items.add(
        'Đã hết ca nhưng chưa ghi nhận giờ ra. Hãy chấm công ra hoặc gửi đơn giải trình.',
      );
    }
    if (checkOut != null && checkOut!.isBefore(scheduledEnd)) {
      items.add('Ra sớm ${scheduledEnd.difference(checkOut!).inMinutes} phút.');
    }
    return items.isEmpty
        ? (checkOut == null ? 'Đang trong ca làm.' : 'Không có bất thường.')
        : items.join(' ');
  }

  double get hours =>
      checkOut == null ? 0 : checkOut!.difference(checkIn).inMinutes / 60;

  Json toJson() => {
    'id': id,
    'employeeId': employeeId,
    'shiftName': shiftName,
    'checkIn': checkIn.toIso8601String(),
    'scheduledEnd': scheduledEnd.toIso8601String(),
    'lateMinutes': lateMinutes,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'checkOut': checkOut?.toIso8601String(),
    'outLatitude': outLatitude,
    'outLongitude': outLongitude,
    'employeeName': employeeName,
  };

  factory Attendance.fromJson(Json j) => Attendance(
    id: j['id']?.toString() ?? '',
    employeeId: j['employeeId']?.toString() ?? '',
    shiftName: j['shiftName']?.toString() ?? '',
    checkIn: DateTime.parse(j['checkIn']).toLocal(),
    scheduledEnd: DateTime.parse(j['scheduledEnd']).toLocal(),
    lateMinutes: (j['lateMinutes'] ?? 0) as int,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    accuracy: (j['accuracy'] as num).toDouble(),
    checkOut: j['checkOut'] == null ? null : DateTime.parse(j['checkOut']).toLocal(),
    outLatitude: (j['outLatitude'] as num?)?.toDouble(),
    outLongitude: (j['outLongitude'] as num?)?.toDouble(),
    employeeName: j['employeeName']?.toString(),
  );
}

class WorkRequest {
  final String id, employeeId;
  String type, reason, status, reviewerNote;
  DateTime from, to;
  int? version;
  String? employeeName;

  WorkRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.reason,
    required this.from,
    required this.to,
    this.status = 'pending',
    this.reviewerNote = '',
    this.version,
    this.employeeName,
  });

  Json toJson() => {
    'id': id,
    'employeeId': employeeId,
    'type': type,
    'reason': reason,
    'from': from.toIso8601String(),
    'to': to.toIso8601String(),
    'status': status,
    'reviewerNote': reviewerNote,
    'version': version,
    'employeeName': employeeName,
  };

  factory WorkRequest.fromJson(Json j) => WorkRequest(
    id: j['id']?.toString() ?? '',
    employeeId: j['employeeId']?.toString() ?? '',
    type: j['type']?.toString() ?? '',
    reason: j['reason']?.toString() ?? '',
    from: DateTime.parse(j['from']),
    to: DateTime.parse(j['to']),
    status: j['status']?.toString() ?? 'pending',
    reviewerNote: j['reviewerNote']?.toString() ?? '',
    version: j['version'] as int?,
    employeeName: j['employeeName']?.toString(),
  );
}

class Office {
  String name, qrSecret;
  double? latitude, longitude;
  double radius;
  bool isServerConfigured;

  Office({
    this.name = 'Văn phòng',
    this.qrSecret = '',
    this.latitude,
    this.longitude,
    this.radius = 150,
    this.isServerConfigured = false,
  });

  bool get configured =>
      (latitude != null && longitude != null && (qrSecret.isNotEmpty || isServerConfigured));

  Json toJson() => {
    'name': name,
    'qrSecret': qrSecret,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'configured': configured,
  };

  factory Office.fromJson(Json j) => Office(
    name: j['name']?.toString() ?? 'Văn phòng',
    qrSecret: j['qrSecret']?.toString() ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    radius: (j['radius'] as num?)?.toDouble() ?? 150,
    isServerConfigured: j['configured'] as bool? ?? (j['latitude'] != null && j['longitude'] != null),
  );
}

class AppData {
  List<Employee> employees;
  List<Department> departments;
  List<Shift> shifts;
  List<Attendance> attendance;
  List<WorkRequest> requests;
  Office office;

  AppData({
    List<Employee>? employees,
    List<Department>? departments,
    List<Shift>? shifts,
    List<Attendance>? attendance,
    List<WorkRequest>? requests,
    Office? office,
  }) : employees = employees ?? [],
       departments = departments ?? [],
       shifts = shifts ?? [],
       attendance = attendance ?? [],
       requests = requests ?? [],
       office = office ?? Office();

  Json toJson() => {
    'version': 1,
    'employees': employees.map((e) => e.toJson()).toList(),
    'departments': departments.map((d) => d.toJson()).toList(),
    'shifts': shifts.map((s) => s.toJson()).toList(),
    'attendance': attendance.map((a) => a.toJson()).toList(),
    'requests': requests.map((r) => r.toJson()).toList(),
    'office': office.toJson(),
  };

  factory AppData.fromJson(Json j) {
    return AppData(
      employees: (j['employees'] as List?)
              ?.map((e) => Employee.fromJson(e))
              .toList() ??
          [],
      departments: (j['departments'] as List?)
              ?.map((d) => Department.fromJson(d))
              .toList() ??
          [],
      shifts: (j['shifts'] as List?)
              ?.map((e) => Shift.fromJson(e))
              .toList() ??
          [],
      attendance: (j['attendance'] as List?)
              ?.map((e) => Attendance.fromJson(e))
              .toList() ??
          [],
      requests: (j['requests'] as List?)
              ?.map((e) => WorkRequest.fromJson(e))
              .toList() ??
          [],
      office: j['office'] != null ? Office.fromJson(j['office']) : Office(),
    );
  }
}
