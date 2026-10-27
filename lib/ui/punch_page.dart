import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_config.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import '../data/face_service.dart';
import '../data/api_client.dart';
import 'biometric_page.dart';
import 'face_camera_page.dart';
import 'face_page.dart';
import 'common.dart';
import 'home_page.dart' show acquirePosition;
import '../widgets/shared_navy_header.dart';

class PunchPage extends StatefulWidget {
  final AppController controller;
  const PunchPage({super.key, required this.controller});
  @override
  State<PunchPage> createState() => _PunchPageState();
}

class _PunchPageState extends State<PunchPage> {
  bool busy = false;
  bool? enrolled;
  bool reconcile = false;
  String? error, result, gpsDetail;
  Position? _freshGps;
  DateTime? _freshGpsAt;
  String? selectedShiftId;
  String? scannedQr;
  int step = -1;
  final done = <int>{};

  // State hỗ trợ flow tối ưu
  bool _gpsChecking = false;
  bool _gpsValid = false;
  int _faceFailCount = 0;

  // Realtime clock
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();

  AppController get c => widget.controller;
  List<Shift> get shifts {
    final items = [...c.data.shifts]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return items;
  }

  Shift? get assignedShift =>
      shifts.where((s) => s.id == c.user?.shiftId).firstOrNull;
  Shift? get shift =>
      shifts.where((s) => s.id == selectedShiftId).firstOrNull ?? assignedShift;

  List<Attendance> get history =>
      c.data.attendance
          .where(
            (a) =>
                a.employeeId == c.user?.id &&
                (dayKey(a.checkIn) == dayKey(DateTime.now()) ||
                    (a.checkOut != null &&
                        dayKey(a.checkOut!) == dayKey(DateTime.now())) ||
                    a.checkOut == null),
          )
          .toList()
        ..sort((a, b) => b.checkIn.compareTo(a.checkIn));

  Attendance? get current {
    if (c.openAttendance != null) return c.openAttendance;
    final s = shift;
    if (s == null) return null;
    var anchor = DateTime.now();
    if (s.endMinute < s.startMinute &&
        anchor.hour * 60 + anchor.minute < s.endMinute) {
      anchor = anchor.subtract(const Duration(days: 1));
    }
    return c.data.attendance
        .where(
          (a) =>
              a.employeeId == c.user?.id &&
              a.shiftName.trim().toLowerCase() == s.name.trim().toLowerCase() &&
              dayKey(a.scheduledEnd) == dayKey(s.endOn(anchor)),
        )
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    selectedShiftId = c.user?.shiftId;
    c.addListener(_changed);
    _loadFace();

    // Khởi động đồng hồ realtime mỗi giây
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        c.syncAll();
        _autoCheckGps();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PunchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
      _loadFace();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (c.user?.shiftId != null && selectedShiftId != c.user?.shiftId) {
      selectedShiftId = c.user?.shiftId;
    } else {
      selectedShiftId ??= c.user?.shiftId;
    }
    setState(() {});
  }

  Future<void> _loadFace() async {
    try {
      final value = await FaceService(c.client).status();
      if (mounted) setState(() => enrolled = value);
    } catch (_) {
      if (mounted) setState(() => enrolled = null);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    c.removeListener(_changed);
    super.dispose();
  }

  Future<void> _account() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Tài khoản • Khuôn mặt')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [FaceSettingsCard(controller: c)],
          ),
        ),
      ),
    );
    if (mounted) {
      await _loadFace();
      if (mounted) setState(() {});
    }
  }

  Future<void> _autoCheckGps({bool force = false}) async {
    if (_gpsChecking) return;
    setState(() {
      _gpsChecking = true;
      error = null;
    });
    try {
      await _gps(force: force);
      if (mounted) {
        setState(() {
          _gpsValid = true;
          done.add(0);
        });
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst(
          RegExp(r'^(Exception: |StateError: |Bad state: )'),
          '',
        );
        setState(() {
          _gpsValid = false;
          done.remove(0);
          error = message;
        });
      }
    } finally {
      if (mounted) setState(() => _gpsChecking = false);
    }
  }

  Future<Position> _gps({bool force = false}) async {
    final cached = _freshGps;
    final cachedAt = _freshGpsAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 40)) {
      return cached;
    }

    Position p;
    try {
      p = await acquirePosition();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('denied')) {
        throw StateError(
          'Chưa cấp quyền truy cập vị trí. Hãy bật quyền GPS trong Cài đặt máy.',
        );
      } else if (msg.contains('disabled') || msg.contains('service')) {
        throw StateError(
          'Chưa bật GPS trên điện thoại. Vui lòng bật định vị vị trí (Location).',
        );
      }
      throw StateError(
        'Không thể lấy tọa độ GPS: ${e.toString().replaceFirst(RegExp(r'^(Exception: |StateError: )'), '')}',
      );
    }

    if (!mounted) throw StateError('Đã rời màn chấm công.');
    final office = c.data.office;
    if (!office.configured) {
      throw StateError('Văn phòng chưa được cấu hình tọa độ. Vui lòng liên hệ Admin.');
    }
    final distance = Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      office.latitude!,
      office.longitude!,
    );
    setState(
      () => gpsDetail =
          'Trong phạm vi • cách nơi làm việc ${distance.round()} m',
    );
    if (p.isMocked) {
      throw StateError(
        'Vị trí giả (Fake GPS) không được chấp nhận. Vui lòng tắt ứng dụng giả lập GPS.',
      );
    }
    if (!p.accuracy.isFinite || p.accuracy < 0 || p.accuracy > 80) {
      throw StateError(
        'GPS quá yếu (sai số ±${p.accuracy.round()} m > cho phép 80 m). Hãy ra nơi thoáng và thử lại.',
      );
    }
    if (distance > office.radius) {
      throw StateError(
        'Bạn đang cách nơi làm việc ${distance.round()} m (cho phép ${office.radius.round()} m). Cần di chuyển vào gần hơn ${(distance - office.radius).ceil()} m.',
      );
    }
    _freshGps = p;
    _freshGpsAt = DateTime.now();
    return p;
  }

  Future<void> _scanWorkplace() async {
    if (busy) return;
    setState(() => error = null);
    final qr = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (!mounted) return;
    if (qr == null || qr.trim().isEmpty) return;
    setState(() {
      scannedQr = qr.trim();
      done.add(1);
      step = 1;
    });
  }

  Future<void> _run({bool useBiometricFallback = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      result = null;
      done.clear();
      step = -1;
    });
    try {
      await c.syncAll();
      if (!mounted) return;
      if (c.syncError != null || c.isSyncing) {
        throw StateError(
          'Chưa cập nhật được ca và lịch sử. Kiểm tra mạng rồi thử lại.',
        );
      }
      if (reconcile) {
        reconcile = false;
        setState(
          () => result =
              'Đã cập nhật lịch sử. Kiểm tra giờ đã ghi nhận trước khi chấm công tiếp.',
        );
        return;
      }
      final attendance = current;
      if (attendance?.checkOut != null) {
        setState(() => result = 'Bạn đã hoàn tất ca này.');
        return;
      }
      if (shift == null && c.openAttendance == null) {
        throw StateError('Hãy chọn ca làm trước khi chấm công.');
      }
      final checkingOut = c.openAttendance != null;
      final openId = c.openAttendance?.id;

      // Bước 1: Kiểm tra vị trí GPS
      setState(() => step = 0);
      var p = await _gps();
      if (!mounted) return;
      setState(() {
        done.add(0);
        _gpsValid = true;
      });

      if (AppConfig.requireQr) {
        setState(() => step = 1);
        var qr = scannedQr;
        if (qr == null || qr.isEmpty) {
          qr = await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const ScannerPage()),
          );
        }
        if (!mounted) return;
        if (qr == null || qr.trim().isEmpty) {
          throw StateError('Hãy bấm Quét QR nơi làm việc, rồi chấm công.');
        }
        scannedQr = qr.trim();
        setState(() => done.add(1));
      }

      // Bước 2: Xác thực khuôn mặt
      final faceStepIndex = AppConfig.requireQr ? 2 : 1;
      setState(() => step = faceStepIndex);

      String? proof;
      if (useBiometricFallback) {
        final bioAuthed = await BiometricLoginHelper.authenticate();
        if (!bioAuthed) {
          throw StateError('Xác thực vân tay không thành công hoặc đã bị hủy.');
        }
        proof = 'biometric_fallback';
      } else {
        final faces = FaceService(c.client);
        final hasFace = await faces.status();
        if (!mounted) return;
        setState(() => enrolled = hasFace);

        if (!hasFace) {
          throw StateError(
            'Bạn chưa đăng ký khuôn mặt. Vui lòng vào mục Tài khoản để đăng ký trước khi chấm công.',
          );
        }

        proof = await showFaceCamera<String>(
          context,
          title: checkingOut
              ? 'Xác thực khuôn mặt để ra ca'
              : 'Xác thực khuôn mặt để vào ca',
          onCapture: (image) =>
              faces.verify(image, checkingOut ? 'check-out' : 'check-in'),
        );
        if (!mounted) return;
        if (proof == null) {
          _faceFailCount++;
          throw StateError(
            'Khuôn mặt không khớp hoặc bạn đã hủy xác thực. Hãy thử lại.',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        done.add(faceStepIndex);
      });

      final gpsAge = _freshGpsAt == null
          ? const Duration(days: 1)
          : DateTime.now().difference(_freshGpsAt!);
      p = await _gps(force: gpsAge > const Duration(seconds: 40));
      if (!mounted) return;

      // Bước 3: Ghi nhận giờ
      final submitStepIndex = AppConfig.requireQr ? 3 : 2;
      setState(() => step = submitStepIndex);

      if (c.openAttendance?.id != openId) {
        throw StateError('Trạng thái ca đã thay đổi. Hãy thử lại.');
      }
      reconcile = true;
      final office = c.data.office;
      final String? qrPayload = AppConfig.requireQr ? scannedQr?.trim() : null;

      final punchTime = DateTime.now();

      await c.punch(
        qr: qrPayload,
        shiftId: checkingOut ? null : shift?.id,
        faceProof: proof,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        distance: Geolocator.distanceBetween(
          p.latitude,
          p.longitude,
          office.latitude!,
          office.longitude!,
        ),
        capturedAt: punchTime.toUtc(),
        mocked: p.isMocked,
      );
      if (!mounted) return;
      if (c.syncError != null) {
        throw StateError(
          'Đã gửi chấm công nhưng chưa tải được kết quả. Thử lại để cập nhật lịch sử.',
        );
      }
      reconcile = false;
      _faceFailCount = 0;
      final saved = checkingOut
          ? c.data.attendance.where((a) => a.id == openId).firstOrNull
          : c.openAttendance;
      setState(() {
        done.add(submitStepIndex);
        scannedQr = null;
        result = saved == null
            ? 'Đã gửi chấm công. Vui lòng kiểm tra lịch sử.'
            : '${checkingOut ? 'Chấm công ra' : 'Chấm công vào'} thành công • ${_timing(saved, checkingOut)}';
      });

      // Hiển thị Dialog chấm công thành công chuẩn Mockup 4
      if (mounted && saved != null) {
        _showSuccessModal(
          context: context,
          attendance: saved,
          isCheckOut: checkingOut,
          punchTime: punchTime,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode >= 400 && e.statusCode < 500) {
        reconcile = false;
      }
      var message = e.toString().replaceFirst(
        RegExp(r'^(Exception: |StateError: |Bad state: )'),
        '',
      );

      if (!AppConfig.requireQr && message.toLowerCase().contains('qr')) {
        message = 'Không thể chấm công: Server API backend vẫn đang bắt buộc kiểm tra mã QR. Hãy cấu hình API backend để bỏ qua điều kiện QR.';
      }

      setState(() {
        error = message;
        if (message.toLowerCase().contains('qr') && AppConfig.requireQr) {
          step = 1;
          done.remove(1);
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static String _timing(Attendance a, bool out) {
    if (out && a.checkOut != null) {
      final early = a.scheduledEnd.difference(a.checkOut!).inMinutes;
      return early > 0 ? 'Về sớm $early phút' : 'Đúng giờ';
    }
    return a.lateMinutes > 0 ? 'Đi trễ ${a.lateMinutes} phút' : 'Đúng giờ';
  }

  void _handlePunchTap({
    required bool canPunch,
    required bool completed,
    required bool inOpenShift,
  }) {
    if (completed) {
      message(context, 'Bạn đã hoàn tất cả giờ vào và giờ ra của ca làm này hôm nay!');
      return;
    }
    if (shift == null && !inOpenShift) {
      message(context, 'Vui lòng chạm để chọn một ca làm việc từ danh sách!');
      return;
    }
    if (!c.data.office.configured) {
      message(context, 'Văn phòng chưa được cấu hình tọa độ GPS. Vui lòng liên hệ Admin.');
      return;
    }
    if (enrolled != true) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.face_retouching_natural, color: Color(0xFF006766)),
              SizedBox(width: 10),
              Text('Chưa đăng ký khuôn mặt', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: const Text(
            'Hệ thống yêu cầu xác thực khuôn mặt khi chấm công. Bạn vui lòng chụp đăng ký khuôn mặt trước.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Để sau'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _account();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006766),
                foregroundColor: Colors.white,
              ),
              child: const Text('Đăng ký ngay'),
            ),
          ],
        ),
      );
      return;
    }
    if (!_gpsValid) {
      message(
        context,
        'Chưa đạt điều kiện vị trí GPS. Hãy kiểm tra bạn đã ở văn phòng và nhấn nút làm mới GPS.',
      );
      return;
    }

    _run();
  }

  // ============================================================================
  // DIALOG THÀNH CÔNG THEO MOCKUP 4
  // ============================================================================
  void _showSuccessModal({
    required BuildContext context,
    required Attendance attendance,
    required bool isCheckOut,
    required DateTime punchTime,
  }) {
    final isLate = !isCheckOut && attendance.lateMinutes > 0;
    final isEarly = isCheckOut && attendance.checkOut != null &&
        attendance.scheduledEnd.difference(attendance.checkOut!).inMinutes > 0;
    final earlyMins = isCheckOut && attendance.checkOut != null
        ? attendance.scheduledEnd.difference(attendance.checkOut!).inMinutes
        : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Icon tick tròn xanh lá lớn
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF86EFAC), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF16A34A),
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  isCheckOut ? 'Chấm công ra thành công' : 'Chấm công vào thành công',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),

                // Giờ to đậm
                Text(
                  clock(punchTime),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF006766),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  _formatVietnameseDate(punchTime),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),

                // Bảng thông tin chi tiết
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        label: 'Ca làm việc',
                        value: attendance.shiftName,
                      ),
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildDetailRow(
                        label: 'Trạng thái',
                        customValue: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isLate || isEarly)
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isLate
                                ? 'Đi trễ ${attendance.lateMinutes} phút'
                                : isEarly
                                    ? 'Về sớm $earlyMins phút'
                                    : 'Đúng giờ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (isLate || isEarly)
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF15803D),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildDetailRow(
                        label: 'Vị trí',
                        value: 'Trong phạm vi nơi làm việc',
                      ),
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildDetailRow(
                        label: 'Xác thực',
                        value: 'Khuôn mặt hợp lệ',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Chú thích ghi chú màu vàng kem
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isLate
                              ? 'Ghi chú: Ca làm việc có 15 phút trừ giờ cho phép. Đi trễ đã được hệ thống ghi nhận.'
                              : 'Ghi chú: Giờ làm việc đã được hệ thống ghi nhận và đồng bộ trực tiếp lên server.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF92400E),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2 nút hành động
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF006766), Color(0xFF004D40)],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Xong', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required String label,
    String? value,
    Widget? customValue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        if (customValue != null)
          customValue
        else
          Text(
            value ?? '',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w700),
          ),
      ],
    );
  }

  String _formatVietnameseDate(DateTime date) {
    const days = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    final dayName = days[date.weekday - 1];
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$dayName, $day/$month/$year';
  }

  String _timeString(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // ============================================================================
  // GIAO DIỆN CHÍNH (MOCKUP 3)
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final a = current;
    final completed = a?.checkOut != null;
    final inOpenShift = c.openAttendance != null;

    final canPunch =
        (shift != null || inOpenShift) &&
        c.data.office.configured &&
        !completed &&
        _gpsValid &&
        enrolled == true;

    final userName = c.user?.name ?? 'Nhân viên';
    final userInitials = userName.isNotEmpty
        ? userName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase()
        : 'NV';

    return RefreshIndicator(
      onRefresh: () async {
        await c.syncAll();
        await _autoCheckGps(force: true);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          // Header xanh Navy uốn cong đồng bộ dùng chung
          SharedNavyHeader(
            title: 'Chấm công',
            controller: c,
            bottomContent: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const GreetingText(),
                      const SizedBox(height: 2),
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006766),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    userInitials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card Trạng thái ca làm việc + Đồng hồ số realtime to
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _formatVietnameseDate(_currentTime),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: completed
                                  ? const Color(0xFFDCFCE7)
                                  : inOpenShift
                                      ? const Color(0xFFE6F3F3)
                                      : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: completed
                                    ? const Color(0xFF86EFAC)
                                    : inOpenShift
                                        ? const Color(0xFF006766).withValues(alpha: 0.3)
                                        : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Text(
                              completed
                                  ? 'Đã hoàn tất ca'
                                  : inOpenShift
                                      ? 'Đang trong ca'
                                      : 'Chưa vào ca',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: completed
                                    ? const Color(0xFF15803D)
                                    : inOpenShift
                                        ? const Color(0xFF006766)
                                        : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Đồng hồ điện tử realtime to rõ ràng
                      Text(
                        _timeString(_currentTime),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: Color(0xFF0A2234),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Thông tin ca làm việc
                      InkWell(
                        onTap: (inOpenShift || busy) ? null : () => _showShiftPickerSheet(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF006766)),
                              const SizedBox(width: 6),
                              Text(
                                shift != null
                                    ? '${shift!.name} • ${_formatMinute(shift!.startMinute)} - ${_formatMinute(shift!.endMinute)}'
                                    : 'Chọn ca làm việc',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              if (!inOpenShift && !busy) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFF64748B)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Card Vị trí GPS theo mockup
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _gpsValid ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          gpsDetail ??
                              (_gpsChecking
                                  ? 'Đang kiểm tra vị trí GPS…'
                                  : 'Chưa xác định được vị trí GPS'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _gpsValid ? const Color(0xFF0F172A) : const Color(0xFF9A3412),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Lấy lại vị trí GPS',
                        icon: _gpsChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006766)),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF006766)),
                        onPressed: (busy || _gpsChecking) ? null : () => _autoCheckGps(force: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Nút Quét QR nếu cấu hình yêu cầu
                if (AppConfig.requireQr) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : _scanWorkplace,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(
                      scannedQr == null ? 'Quét QR nơi làm việc' : 'Đã quét QR • Quét lại',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Nút tròn chấm công to ở giữa (Circular Punch Button) chuẩn Mockup 3
                Center(
                  child: GestureDetector(
                    onTap: !busy
                        ? () => _handlePunchTap(
                              canPunch: canPunch,
                              completed: completed,
                              inOpenShift: inOpenShift,
                            )
                        : null,
                    child: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: canPunch
                              ? (inOpenShift
                                  ? [const Color(0xFFEA580C), const Color(0xFFC2410C)]
                                  : [const Color(0xFF006766), const Color(0xFF004D40)])
                              : [const Color(0xFF64748B), const Color(0xFF475569)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (canPunch
                                    ? (inOpenShift ? const Color(0xFFEA580C) : const Color(0xFF006766))
                                    : const Color(0xFF64748B))
                                .withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy)
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          else ...[
                            Icon(
                              inOpenShift
                                  ? Icons.logout_rounded
                                  : Icons.face_retouching_natural_rounded,
                              size: 42,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              completed
                                  ? 'Hoàn tất'
                                  : inOpenShift
                                      ? 'Chấm công ra'
                                      : 'Chấm công vào',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Nút phụ: Dùng vân tay thay thế khi camera khuôn mặt gặp sự cố
                if (_faceFailCount >= 1 && (shift != null || inOpenShift) && _gpsValid) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: busy ? null : () => _run(useBiometricFallback: true),
                      icon: const Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF006766)),
                      label: const Text(
                        'Dùng vân tay thiết bị để thay thế',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF006766),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),

                // Stepper ngang 3 bước theo mockup
                _buildHorizontalStepper(),
                const SizedBox(height: 20),

                // Thông báo lỗi nếu có
                if (error != null) ...[
                  _PunchError(
                    message: error!,
                    onRetry: busy ? null : () => _run(),
                    onAccount: enrolled == false && !busy ? _account : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Thẻ tóm tắt Lịch sử hôm nay theo mockup
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Hôm nay',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${history.length} lượt',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Chưa có dữ liệu chấm công hôm nay.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          ),
                        )
                      else
                        for (final item in history) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF006766).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.access_time_rounded,
                                    size: 18,
                                    color: Color(0xFF006766),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.shiftName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Vào: ${clock(item.checkIn)} • Ra: ${clock(item.checkOut)}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: item.lateMinutes > 0
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.lateMinutes > 0 ? 'Trễ ${item.lateMinutes}p' : 'Đúng giờ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: item.lateMinutes > 0
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF15803D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Stepper ngang 3 bước chuẩn Mockup 3
  Widget _buildHorizontalStepper() {
    final steps = [
      {'label': 'Vị trí', 'index': 0},
      {'label': 'Khuôn mặt', 'index': AppConfig.requireQr ? 2 : 1},
      {'label': 'Ghi nhận', 'index': AppConfig.requireQr ? 3 : 2},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Flexible(
              child: _buildStepItem(
                number: i + 1,
                title: steps[i]['label'] as String,
                isDone: done.contains(steps[i]['index'] as int),
                isActive: step == (steps[i]['index'] as int),
              ),
            ),
            if (i < steps.length - 1)
              Container(
                width: 14,
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: done.contains(steps[i]['index'] as int)
                    ? const Color(0xFF006766)
                    : const Color(0xFFCBD5E1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepItem({
    required int number,
    required String title,
    required bool isDone,
    required bool isActive,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? const Color(0xFF006766)
                : isActive
                    ? const Color(0xFFE6F3F3)
                    : const Color(0xFFF1F5F9),
            border: Border.all(
              color: isDone
                  ? const Color(0xFF006766)
                  : isActive
                      ? const Color(0xFF006766)
                      : const Color(0xFFCBD5E1),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? const Color(0xFF006766) : const Color(0xFF64748B),
                  ),
                ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isDone || isActive ? FontWeight.w700 : FontWeight.w500,
              color: isDone || isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  void _showShiftPickerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Chọn ca làm việc',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final s in shifts) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_rounded, color: Color(0xFF006766)),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${_formatMinute(s.startMinute)} - ${_formatMinute(s.endMinute)}'),
                  trailing: s.id == (shift?.id)
                      ? const Icon(Icons.check_circle, color: Color(0xFF006766))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => selectedShiftId = s.id);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatMinute(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _PunchError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry, onAccount;
  const _PunchError({required this.message, this.onRetry, this.onAccount});
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              if (onAccount != null)
                TextButton.icon(
                  onPressed: onAccount,
                  icon: const Icon(Icons.person),
                  label: const Text('Mở Tài khoản'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool returned = false;
  bool enteringManually = false;

  Future<void> _manual() async {
    if (returned || enteringManually) return;
    setState(() => enteringManually = true);
    try {
      await editForm(
        context,
        title: 'Nhập mã QR thủ công',
        fields: {'Mã QR': ''},
        save: (values) async {
          final code = values['Mã QR']!.trim();
          if (!code.startsWith('BAOAN:')) {
            throw ArgumentError('Mã QR phải bắt đầu bằng BAOAN:.');
          }
          returned = true;
          manualCode = code;
        },
      );
      if (mounted && manualCode != null) Navigator.pop(context, manualCode);
    } finally {
      if (mounted) setState(() => enteringManually = false);
    }
  }

  String? manualCode;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!scanner.value.isInitialized || returned) return;
    if (state == AppLifecycleState.resumed) {
      scanner.start();
    } else {
      scanner.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét QR văn phòng')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Đưa mã QR vào camera. Mã đổi mỗi phút; lấy mã mới nếu hết hạn.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            controller: scanner,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Không mở được camera. Hãy cấp quyền Camera trong Settings hoặc kiểm tra thiết bị.',
                ),
              ),
            ),
            onDetect: (capture) {
              final value = capture.barcodes
                  .where((b) => b.rawValue?.startsWith('BAOAN:') ?? false)
                  .firstOrNull
                  ?.rawValue;
              if (value != null && !returned && !enteringManually) {
                returned = true;
                Navigator.pop(context, value);
              }
            },
          ),
        ),
        SafeArea(
          top: false,
          child: TextButton(
            onPressed: enteringManually ? null : _manual,
            child: const Text('Nhập mã thủ công'),
          ),
        ),
      ],
    ),
  );
}
