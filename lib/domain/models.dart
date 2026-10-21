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
    id: j['id'],
    name: j['name'],
    email: j['email'],
    username: j['username'],
    department: j['department'],
    role: j['role'],
    passwordHash: j['passwordHash'],
    salt: j['salt'],
    shiftId: j['shiftId'],
    active: j['active'],
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
    'start': startMinute,
    'end': endMinute,
    'grace': grace,
  };
  factory Shift.fromJson(Json j) => Shift(
    id: j['id'],
    name: j['name'],
    startMinute: j['start'],
    endMinute: j['end'],
    grace: j['grace'],
  );
}

class Attendance {
  final String id, employeeId, shiftName;
  final DateTime checkIn, scheduledEnd;
  final int lateMinutes;
  final double latitude, longitude, accuracy;
  DateTime? checkOut;
  double? outLatitude, outLongitude;
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
  };
  factory Attendance.fromJson(Json j) => Attendance(
    id: j['id'],
    employeeId: j['employeeId'],
    shiftName: j['shiftName'],
    checkIn: DateTime.parse(j['checkIn']),
    scheduledEnd: DateTime.parse(j['scheduledEnd']),
    lateMinutes: j['lateMinutes'],
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    accuracy: (j['accuracy'] as num).toDouble(),
    checkOut: j['checkOut'] == null ? null : DateTime.parse(j['checkOut']),
    outLatitude: (j['outLatitude'] as num?)?.toDouble(),
    outLongitude: (j['outLongitude'] as num?)?.toDouble(),
  );
}

class WorkRequest {
  final String id, employeeId;
  String type, reason, status, reviewerNote;
  DateTime from, to;
  WorkRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.reason,
    required this.from,
    required this.to,
    this.status = 'pending',
    this.reviewerNote = '',
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
  };
  factory WorkRequest.fromJson(Json j) => WorkRequest(
    id: j['id'],
    employeeId: j['employeeId'],
    type: j['type'],
    reason: j['reason'],
    from: DateTime.parse(j['from']),
    to: DateTime.parse(j['to']),
    status: j['status'],
    reviewerNote: j['reviewerNote'],
  );
}

class Office {
  String name, qrSecret;
  double? latitude, longitude;
  double radius;
  Office({
    this.name = 'Văn phòng',
    this.qrSecret = '',
    this.latitude,
    this.longitude,
    this.radius = 150,
  });
  bool get configured =>
      latitude != null && longitude != null && qrSecret.isNotEmpty;
  Json toJson() => {
    'name': name,
    'qrSecret': qrSecret,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
  };
  factory Office.fromJson(Json j) => Office(
    name: j['name'],
    qrSecret: j['qrSecret'],
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    radius: (j['radius'] as num).toDouble(),
  );
}

class AppData {
  List<Employee> employees;
  List<Shift> shifts;
  List<Attendance> attendance;
  List<WorkRequest> requests;
  Office office;
  AppData({
    List<Employee>? employees,
    List<Shift>? shifts,
    List<Attendance>? attendance,
    List<WorkRequest>? requests,
    Office? office,
  }) : employees = employees ?? [],
       shifts = shifts ?? [],
       attendance = attendance ?? [],
       requests = requests ?? [],
       office = office ?? Office();
  Json toJson() => {
    'version': 1,
    'employees': employees.map((e) => e.toJson()).toList(),
    'shifts': shifts.map((s) => s.toJson()).toList(),
    'attendance': attendance.map((a) => a.toJson()).toList(),
    'requests': requests.map((r) => r.toJson()).toList(),
    'office': office.toJson(),
  };
  factory AppData.fromJson(Json j) {
    if (j['version'] != 1) {
      throw const FormatException('Phiên bản dữ liệu chưa được hỗ trợ.');
    }
    return AppData(
      employees: (j['employees'] as List)
          .map((e) => Employee.fromJson(e))
          .toList(),
      shifts: (j['shifts'] as List).map((e) => Shift.fromJson(e)).toList(),
      attendance: (j['attendance'] as List)
          .map((e) => Attendance.fromJson(e))
          .toList(),
      requests: (j['requests'] as List)
          .map((e) => WorkRequest.fromJson(e))
          .toList(),
      office: Office.fromJson(j['office']),
    );
  }
}
