import 'dart:math';

typedef Json = Map<String, dynamic>;

// API instants must carry a timezone. Date-only values use DateTime.parse separately.
DateTime parseApiInstant(Object? value) {
  final text = value?.toString() ?? '';
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(text)) {
    throw FormatException('API thiếu múi giờ Z/offset', text);
  }
  return DateTime.parse(text).toUtc().toLocal();
}

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
  String approvalStatus;

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
    this.approvalStatus = 'Approved',
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
    'approvalStatus': approvalStatus,
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
    approvalStatus: j['approvalStatus']?.toString() ?? 'Approved',
  );
}

class Department {
  final String id;
  String name;
  String? description;

  Department({required this.id, required this.name, this.description});

  Json toJson() => {'id': id, 'name': name, 'description': description};

  factory Department.fromJson(Json j) => Department(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
  );
}

class Shift {
  final String id;
  String name;
  int startMinute, endMinute, grace, breakMinutes, earlyLeaveGraceMinutes;

  Shift({
    required this.id,
    required this.name,
    required this.startMinute,
    required this.endMinute,
    this.grace = 5,
    this.breakMinutes = 0,
    this.earlyLeaveGraceMinutes = 5,
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
    'breakMinutes': breakMinutes,
    'earlyLeaveGraceMinutes': earlyLeaveGraceMinutes,
  };

  factory Shift.fromJson(Json j) => Shift(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    startMinute: (j['startMinute'] ?? j['start'] ?? 0) as int,
    endMinute: (j['endMinute'] ?? j['end'] ?? 0) as int,
    grace: (j['grace'] ?? 5) as int,
    breakMinutes: (j['breakMinutes'] as num?)?.toInt() ?? 0,
    earlyLeaveGraceMinutes: (j['earlyLeaveGraceMinutes'] as num?)?.toInt() ?? 5,
  );
}

class Attendance {
  final String id, employeeId, shiftName;
  final DateTime checkIn, scheduledEnd;
  final DateTime? scheduledStart, autoClosedAt;
  final int lateMinutes, earlyLeaveMinutes, breakMinutes, expectedMinutes;
  final int earlyLeaveGraceMinutes;
  final int? netMinutes;
  final bool isAutoClosed;
  final String status;
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
    this.scheduledStart,
    this.autoClosedAt,
    this.earlyLeaveMinutes = 0,
    this.breakMinutes = 0,
    this.expectedMinutes = 0,
    this.earlyLeaveGraceMinutes = 0,
    this.netMinutes,
    this.isAutoClosed = false,
    this.status = 'BatThuong',
  });

  bool get isAbnormal => status.split(',').any((s) => s.trim() == 'BatThuong');
  bool get hasActualCheckout =>
      checkOut != null &&
      !isAutoClosed &&
      checkOut!.isAfter(checkIn) &&
      !isAbnormal;
  double get hours =>
      hasActualCheckout ? (netMinutes ?? 0).clamp(0, 2147483647) / 60 : 0;

  String get explanation {
    if (isAutoClosed) {
      return 'Quên check-out. Ca tự đóng, chưa được tính giờ công.';
    }
    if (isAbnormal) {
      return 'Bất thường: cần đối soát bản ghi trước khi tính công.';
    }
    final parts = <String>[
      if (lateMinutes > 0) 'Đi trễ $lateMinutes phút (đã trừ dung sai).',
      if (earlyLeaveMinutes > 0)
        'Về sớm $earlyLeaveMinutes phút (đã trừ dung sai).',
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return checkOut == null ? 'Đang trong ca, chưa có giờ ra.' : 'Đúng giờ.';
  }

  Json toJson() => {
    'id': id,
    'employeeId': employeeId,
    'shiftName': shiftName,
    'checkIn': checkIn.toUtc().toIso8601String(),
    'scheduledEnd': scheduledEnd.toUtc().toIso8601String(),
    'scheduledStart': scheduledStart?.toUtc().toIso8601String(),
    'checkOut': checkOut?.toUtc().toIso8601String(),
    'autoClosedAt': autoClosedAt?.toUtc().toIso8601String(),
    'lateMinutes': lateMinutes,
    'earlyLeaveMinutes': earlyLeaveMinutes,
    'breakMinutes': breakMinutes,
    'expectedMinutes': expectedMinutes,
    'earlyLeaveGraceMinutes': earlyLeaveGraceMinutes,
    'netMinutes': netMinutes,
    'isAutoClosed': isAutoClosed,
    'status': status,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'outLatitude': outLatitude,
    'outLongitude': outLongitude,
    'employeeName': employeeName,
  };
  factory Attendance.fromJson(Json j) => Attendance(
    id: j['id'].toString(),
    employeeId: j['employeeId'].toString(),
    shiftName: j['shiftName']?.toString() ?? '',
    checkIn: parseApiInstant(j['checkIn']),
    scheduledEnd: parseApiInstant(j['scheduledEnd']),
    scheduledStart: j['scheduledStart'] == null
        ? null
        : parseApiInstant(j['scheduledStart']),
    checkOut: j['checkOut'] == null ? null : parseApiInstant(j['checkOut']),
    autoClosedAt: j['autoClosedAt'] == null
        ? null
        : parseApiInstant(j['autoClosedAt']),
    lateMinutes: (j['lateMinutes'] as num?)?.toInt() ?? 0,
    earlyLeaveMinutes: (j['earlyLeaveMinutes'] as num?)?.toInt() ?? 0,
    breakMinutes: (j['breakMinutes'] as num?)?.toInt() ?? 0,
    expectedMinutes: (j['expectedMinutes'] as num?)?.toInt() ?? 0,
    earlyLeaveGraceMinutes: (j['earlyLeaveGraceMinutes'] as num?)?.toInt() ?? 0,
    netMinutes: (j['netMinutes'] as num?)?.toInt(),
    isAutoClosed: j['isAutoClosed'] as bool? ?? false,
    status: j['status']?.toString() ?? 'BatThuong',
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    accuracy: (j['accuracy'] as num).toDouble(),
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
  int days;
  String? reviewedBy, reviewerName;
  DateTime? reviewedAt;
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
    this.days = 0,
    this.reviewedBy,
    this.reviewerName,
    this.reviewedAt,
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
    'days': days,
    'reviewedBy': reviewedBy,
    'reviewerName': reviewerName,
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
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
    days: (j['days'] as num?)?.toInt() ?? 0,
    reviewedBy: j['reviewedBy']?.toString(),
    reviewerName: j['reviewerName']?.toString(),
    reviewedAt: j['reviewedAt'] == null
        ? null
        : parseApiInstant(j['reviewedAt']),
    employeeName: j['employeeName']?.toString(),
  );
}

class Office {
  String name, qrSecret;
  double? latitude, longitude;
  double radius;
  bool isServerConfigured;

  Office({
    this.name = 'Văn phòng chính',
    this.qrSecret = '',
    this.latitude,
    this.longitude,
    this.radius = 100,
    this.isServerConfigured = false,
  });

  bool get configured =>
      (latitude != null &&
      longitude != null &&
      (qrSecret.isNotEmpty || isServerConfigured));

  Json toJson() => {
    'name': name,
    'qrSecret': qrSecret,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'configured': configured,
  };

  factory Office.fromJson(Json j) => Office(
    name: j['name']?.toString() ?? 'Văn phòng chính',
    qrSecret: j['qrSecret']?.toString() ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    radius: (j['radius'] as num?)?.toDouble() ?? 100,
    isServerConfigured:
        j['configured'] as bool? ??
        (j['latitude'] != null && j['longitude'] != null),
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
      employees:
          (j['employees'] as List?)
              ?.map((e) => Employee.fromJson(e))
              .toList() ??
          [],
      departments:
          (j['departments'] as List?)
              ?.map((d) => Department.fromJson(d))
              .toList() ??
          [],
      shifts:
          (j['shifts'] as List?)?.map((e) => Shift.fromJson(e)).toList() ?? [],
      attendance:
          (j['attendance'] as List?)
              ?.map((e) => Attendance.fromJson(e))
              .toList() ??
          [],
      requests:
          (j['requests'] as List?)
              ?.map((e) => WorkRequest.fromJson(e))
              .toList() ??
          [],
      office: j['office'] != null ? Office.fromJson(j['office']) : Office(),
    );
  }
}
