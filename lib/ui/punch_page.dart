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
    // 2. GPS tự động chạy ngay khi mở màn chấm công
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoCheckGps();
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
    selectedShiftId ??= c.user?.shiftId;
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

  // 2 & 7. Tự động kiểm tra GPS khi vào màn hình hoặc bấm nút làm mới nhỏ
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
          done.add(0); // Bước 1: GPS hoàn tất
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

  // 7. Lấy GPS với thông báo lỗi cụ thể, rõ lý do
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
          'Cách văn phòng ${distance.round()} m • Bán kính cho phép ${office.radius.round()} m • Sai số ±${p.accuracy.round()} m',
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
        'Bạn đang cách văn phòng ${distance.round()} m (cho phép ${office.radius.round()} m). Cần di chuyển vào gần hơn ${(distance - office.radius).ceil()} m.',
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

  // 4 & 6. Flow chấm công mới: Bấm nút -> Quét mặt -> Tự động ghi nhận (tối đa 2 chạm)
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

      // 1. Nếu requireQr = true thì mới yêu cầu quét QR văn phòng
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

      // Bước 2: Xác thực khuôn mặt (Bắt buộc) hoặc vân tay dự phòng
      final faceStepIndex = AppConfig.requireQr ? 2 : 1;
      setState(() => step = faceStepIndex);

      String? proof;
      if (useBiometricFallback) {
        // 6. Phương án dự phòng: Vân tay điện thoại
        final bioAuthed = await BiometricLoginHelper.authenticate();
        if (!bioAuthed) {
          throw StateError('Xác thực vân tay không thành công hoặc đã bị hủy.');
        }
        proof = 'biometric_fallback';
      } else {
        // 5. Khuôn mặt là bắt buộc
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

      // Kiểm tra lại GPS tươi trước khi ghi nhận
      final gpsAge = _freshGpsAt == null
          ? const Duration(days: 1)
          : DateTime.now().difference(_freshGpsAt!);
      p = await _gps(force: gpsAge > const Duration(seconds: 40));
      if (!mounted) return;

      // Bước 3: Tự động gửi và ghi nhận giờ (không bắt bấm thêm nút)
      final submitStepIndex = AppConfig.requireQr ? 3 : 2;
      setState(() => step = submitStepIndex);

      if (c.openAttendance?.id != openId) {
        throw StateError('Trạng thái ca đã thay đổi. Hãy thử lại.');
      }
      reconcile = true;
      final office = c.data.office;

      // 2. Nếu requireQr = false thì không đính kèm mã QR
      final String? qrPayload = AppConfig.requireQr ? scannedQr?.trim() : null;

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
        capturedAt: DateTime.now().toUtc(),
        mocked: p.isMocked,
      );
      if (!mounted) return;
      if (c.syncError != null) {
        throw StateError(
          'Đã gửi chấm công nhưng chưa tải được kết quả. Thử lại để cập nhật lịch sử.',
        );
      }
      reconcile = false;
      _faceFailCount = 0; // Reset số lần fail
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
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode >= 400 && e.statusCode < 500) {
        reconcile = false;
      }
      var message = e.toString().replaceFirst(
        RegExp(r'^(Exception: |StateError: |Bad state: )'),
        '',
      );

      // 3. Thông báo 'QR sai hoặc hết hạn' chỉ hiển thị khi requireQr = true.
      // Khi requireQr = false, nếu server vẫn báo lỗi QR thì giải thích rõ nguyên nhân do API backend.
      if (!AppConfig.requireQr && message.toLowerCase().contains('qr')) {
        message = 'Không thể chấm công: Server API backend vẫn đang bắt buộc kiểm tra mã QR (ValidatePunch). Hãy cập nhật API backend để bỏ qua điều kiện QR.';
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

  // ============================================================================
  // GIAO DIỆN CHÍNH MÀN CHẤM CÔNG
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final a = current;
    final completed = a?.checkOut != null;
    final inOpenShift = c.openAttendance != null;

    // 4 & 5. Nút chính CHỈ BẬT khi:
    // - GPS hợp lệ (_gpsValid == true)
    // - Đã đăng ký khuôn mặt (enrolled == true)
    // - Ca hợp lệ và chưa hoàn tất
    final canPunch =
        (shift != null || inOpenShift) &&
        c.data.office.configured &&
        !completed &&
        _gpsValid &&
        enrolled == true;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ShiftPicker(
          shifts: shifts,
          assignedId: c.user?.shiftId,
          selectedId: shift?.id,
          attendance: a,
          locked: inOpenShift || busy,
          onSelect: (id) {
            if (inOpenShift || busy) return;
            setState(() {
              selectedShiftId = id;
              error = null;
              result = null;
            });
          },
        ),
        const SizedBox(height: 16),

        // Khối thông tin văn phòng & Trạng thái GPS
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.business_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${c.data.office.name} • Bán kính ${c.data.office.radius.round()} m',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!c.data.office.configured)
                  const Text(
                    'Văn phòng chưa được cấu hình. Vui lòng liên hệ Admin.',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),

                // 2. Trạng thái GPS tự động kèm nút icon làm mới nhỏ bên cạnh
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _gpsValid ? Icons.check_circle_rounded : Icons.location_on_outlined,
                      size: 18,
                      color: _gpsValid ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gpsDetail ??
                            (_gpsChecking
                                ? 'Đang tự động kiểm tra vị trí GPS…'
                                : 'Chưa xác định GPS vị trí hiện tại'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _gpsValid ? Colors.green.shade800 : Colors.black87,
                          fontWeight: _gpsValid ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Lấy lại GPS hiện tại',
                      icon: _gpsChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: busy || _gpsChecking
                          ? null
                          : () => _autoCheckGps(force: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // 5. Cảnh báo bắt buộc đăng ký khuôn mặt nếu chưa đăng ký
        if (enrolled == false) ...[
          Card(
            color: const Color(0xFFFEF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFFECACA)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Bắt buộc đăng ký khuôn mặt',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Để tránh chấm công hộ, hệ thống yêu cầu nhân viên phải đăng ký khuôn mặt trước khi điểm danh. Nút chấm công sẽ được mở sau khi bạn hoàn tất đăng ký.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF7F1D1D), height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: busy ? null : _account,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE2E2),
                      foregroundColor: const Color(0xFF991B1B),
                    ),
                    child: const Text('Đến màn Đăng ký khuôn mặt ngay'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 1. Chỉ hiển thị nút Quét QR khi cờ requireQr = true
        if (AppConfig.requireQr) ...[
          OutlinedButton.icon(
            onPressed: busy ? null : _scanWorkplace,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(
              scannedQr == null
                  ? 'Quét QR nơi làm việc'
                  : 'Đã quét QR • Quét lại',
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4. Nút chính "Chấm công vào / ra"
        _PunchButton(
          busy: busy,
          label: completed
              ? 'Đã hoàn tất ca này'
              : inOpenShift
              ? 'Chấm công ra'
              : 'Chấm công vào ca đã chọn',
          onPressed: !busy && canPunch ? () => _run() : null,
        ),

        // 6. Nút phụ: Dùng vân tay thay thế (khi camera lỗi hoặc thất bại xác thực)
        if (_faceFailCount >= 1 && (shift != null || inOpenShift) && _gpsValid) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _run(useBiometricFallback: true),
            icon: const Icon(Icons.fingerprint_rounded, size: 20),
            label: const Text('Dùng vân tay thay thế (dự phòng)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: const Color(0xFF0F7C8A),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // 3. Danh sách các bước: 3 bước khi requireQr = false
        _StepChecklist(
          active: step,
          done: done,
          failed: error != null,
          gpsDetail: gpsDetail,
          requireQr: AppConfig.requireQr,
        ),

        // Thông báo lỗi chi tiết
        if (error != null)
          _PunchError(
            message: error!,
            onRetry: busy ? null : () => _run(),
            onAccount: enrolled == false && !busy ? _account : null,
          ),

        if (result != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              result!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        const SizedBox(height: 20),
        Section(
          title: 'Lịch sử chấm công hôm nay',
          subtitle: 'Giờ đã được ghi nhận trên hệ thống',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (history.isEmpty)
                const Text('Chưa có lượt chấm công hôm nay.'),
              for (final item in history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.shiftName),
                  subtitle: Text(
                    'Vào: ${clock(item.checkIn)} • Ra: ${clock(item.checkOut)}\n'
                    '${item.checkOut == null ? 'Đang trong ca' : 'Đã hoàn tất'} • ${_timing(item, false)}'
                    '${item.checkOut != null ? ' • ${_timing(item, true)}' : ''}',
                  ),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftPicker extends StatelessWidget {
  final List<Shift> shifts;
  final String? assignedId;
  final String? selectedId;
  final Attendance? attendance;
  final bool locked;
  final ValueChanged<String> onSelect;
  const _ShiftPicker({
    required this.shifts,
    required this.assignedId,
    required this.selectedId,
    required this.attendance,
    required this.locked,
    required this.onSelect,
  });
  String _time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Section(
    title: 'Chọn ca làm',
    subtitle: attendance == null
        ? (AppConfig.requireQr
            ? 'Bấm vào ca để chọn, rồi quét QR nơi làm việc'
            : 'Chọn ca làm việc, GPS tự nhận diện vị trí')
        : attendance!.checkOut == null
        ? 'Đang trong ca • bấm nút để chấm công ra'
        : 'Ca này đã hoàn tất',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shifts.isEmpty)
          const Text(
            'Admin chưa tạo ca làm. Liên hệ Admin trước khi chấm công.',
          ),
        for (final item in shifts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: item.id == selectedId
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                enabled: !locked || item.name == attendance?.shiftName,
                selected: item.id == selectedId,
                title: Text(item.name),
                subtitle: Text(
                  '${_time(item.startMinute)} – ${_time(item.endMinute)}'
                  '${item.id == assignedId ? ' • Ca đã chọn / phân' : ''}',
                ),
                trailing: item.id == selectedId
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.radio_button_unchecked),
                onTap: locked ? null : () => onSelect(item.id),
              ),
            ),
          ),
        if (attendance != null)
          Text('Giờ vào thực tế: ${clock(attendance!.checkIn)}'),
      ],
    ),
  );
}

class _PunchButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onPressed;
  const _PunchButton({required this.busy, required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        backgroundColor: const Color(0xFF0F7C8A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.face_retouching_natural_rounded),
      label: Text(
        busy ? 'Đang xử lý…' : label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

// 3. Danh sách bước linh hoạt: 3 bước khi requireQr = false, 4 bước khi requireQr = true
class _StepChecklist extends StatelessWidget {
  final int active;
  final Set<int> done;
  final bool failed;
  final bool requireQr;
  final String? gpsDetail;
  const _StepChecklist({
    required this.active,
    required this.done,
    required this.failed,
    required this.requireQr,
    this.gpsDetail,
  });

  @override
  Widget build(BuildContext context) {
    final labels = requireQr
        ? [
            'Kiểm tra vị trí GPS',
            'Quét QR văn phòng',
            'Xác thực khuôn mặt',
            'Gửi và ghi nhận giờ',
          ]
        : [
            'Kiểm tra vị trí GPS',
            'Xác thực khuôn mặt',
            'Gửi và ghi nhận giờ',
          ];

    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: done.contains(i)
                ? const Icon(Icons.check_circle, color: Colors.green)
                : active == i && !failed
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    active == i && failed
                        ? Icons.error_outline
                        : Icons.radio_button_unchecked,
                    color: active == i && failed
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
            title: Text('${i + 1}. ${labels[i]}'),
            subtitle: i == 0 && gpsDetail != null
                ? Text(gpsDetail!)
                : (requireQr && i == 1 && done.contains(1))
                ? const Text('Đã nhận mã; server kiểm tra khi ghi giờ.')
                : null,
          ),
      ],
    );
  }
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
