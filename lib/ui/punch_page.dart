import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/app_controller.dart';
import '../domain/models.dart';
import '../data/face_service.dart';
import '../data/api_client.dart';
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
    if (mounted) await _loadFace();
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
    final p = await acquirePosition();
    if (!mounted) throw StateError('Đã rời màn chấm công.');
    final office = c.data.office;
    if (!office.configured) {
      throw StateError('Văn phòng chưa được cấu hình. Liên hệ Admin.');
    }
    final distance = Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      office.latitude!,
      office.longitude!,
    );
    setState(
      () => gpsDetail =
          'Cách văn phòng ${distance.round()} m • Sai số ±${p.accuracy.round()} m',
    );
    if (p.isMocked) {
      throw StateError(
        'Vị trí giả không được chấp nhận. Hãy tắt ứng dụng giả lập GPS.',
      );
    }
    if (!p.accuracy.isFinite || p.accuracy < 0 || p.accuracy > 80) {
      throw StateError(
        'GPS yếu (sai số vượt 80 m). Hãy đến nơi thoáng và thử lại.',
      );
    }
    if (distance > office.radius) {
      throw StateError(
        distance > 2000
            ? 'Bạn cách điểm văn phòng trên hệ thống ${distance.round()} m. Tọa độ đang lưu rất lệch chỗ bạn đứng. Admin hãy mở QR văn phòng → Cấu hình → Lấy GPS tại chỗ làm thật, rồi thử lại.'
            : 'Ngoài bán kính văn phòng. Cần đến gần thêm ${(distance - office.radius).ceil()} m.',
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

  Future<void> _run() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      result = null;
      done.clear();
      step = -1;
    });
    try {
      // Refresh before choosing in/out, also reconciling an uncertain prior request.
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
      setState(() => step = 0);
      var p = await _gps();
      if (!mounted) return;
      setState(() {
        done.add(0);
        step = 1;
      });
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
      setState(() {
        done.add(1);
        step = 2;
      });
      final faces = FaceService(c.client);
      final hasFace = await faces.status();
      if (!mounted) return;
      setState(() => enrolled = hasFace);
      String? proof;
      if (hasFace) {
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
          throw StateError('Đã hủy xác thực khuôn mặt. Hãy thử lại.');
        }
      }
      if (!mounted) return;
      setState(() {
        done.add(2);
        step = 0;
        done.remove(0);
      });
      final gpsAge = _freshGpsAt == null
          ? const Duration(days: 1)
          : DateTime.now().difference(_freshGpsAt!);
      p = await _gps(force: gpsAge > const Duration(seconds: 40));
      if (!mounted) return;
      setState(() {
        done.add(0);
        step = 3;
      });
      if (c.openAttendance?.id != openId) {
        throw StateError('Trạng thái ca đã thay đổi. Hãy thử lại.');
      }
      reconcile = true;
      final office = c.data.office;
      await c.punch(
        qr: scannedQr!.trim(),
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
      final saved = checkingOut
          ? c.data.attendance.where((a) => a.id == openId).firstOrNull
          : c.openAttendance;
      setState(() {
        done.add(3);
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
      final message = e.toString().replaceFirst(
        RegExp(r'^(Exception: |StateError: |Bad state: )'),
        '',
      );
      setState(() {
        error = message;
        if (message.toLowerCase().contains('qr')) {
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

  @override
  Widget build(BuildContext context) {
    final a = current;
    final completed = a?.checkOut != null;
    final inOpenShift = c.openAttendance != null;
    final allowed =
        (shift != null || inOpenShift) &&
        c.data.office.configured &&
        !completed;
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
        Text(
          '${c.data.office.name} • Bán kính ${c.data.office.radius.round()} m',
        ),
        if (!c.data.office.configured)
          const Text('Văn phòng chưa được cấu hình. Vui lòng liên hệ Admin.'),
        if (gpsDetail != null) Text(gpsDetail!),
        const SizedBox(height: 8),
        Text(
          enrolled == null
              ? 'Khuôn mặt: chưa kiểm tra được'
              : enrolled!
              ? 'Khuôn mặt: đã đăng ký'
              : 'Khuôn mặt: Chưa đăng ký',
        ),
        if (enrolled == false) ...[
          const Text(
            'Chưa đăng ký khuôn mặt: chấm công bằng GPS + QR. Đăng ký mẫu nếu muốn khóa chấm hộ bằng mặt.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : _account,
              child: const Text('Mở Tài khoản để đăng ký'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : _scanWorkplace,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(
            scannedQr == null
                ? 'Quét QR nơi làm việc'
                : 'Đã quét QR • Quét lại',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() => error = null);
                  try {
                    await _gps(force: true);
                  } catch (e) {
                    if (!mounted) return;
                    setState(
                      () => error = e.toString().replaceFirst(
                        RegExp(r'^(Exception: |StateError: |Bad state: )'),
                        '',
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.my_location_outlined),
          label: const Text('Kiểm tra GPS hiện tại'),
        ),
        const SizedBox(height: 16),
        _PunchButton(
          busy: busy,
          label: completed
              ? 'Đã hoàn tất ca này'
              : inOpenShift
              ? 'Chấm công ra'
              : 'Chấm công vào ca đã chọn',
          onPressed: !busy && allowed ? _run : null,
        ),
        const SizedBox(height: 16),
        _StepChecklist(
          active: step,
          done: done,
          failed: error != null,
          gpsDetail: gpsDetail,
          faceRequired: enrolled == true,
        ),
        if (error != null)
          _PunchError(
            message: error!,
            onRetry: busy ? null : _run,
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
        ? 'Bấm vào ca để chọn, rồi quét QR nơi làm việc'
        : attendance!.checkOut == null
        ? 'Đang trong ca • hãy quét QR để chấm ra'
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
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
      icon: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fingerprint),
      label: Text(busy ? 'Đang xác minh…' : label),
    ),
  );
}

class _StepChecklist extends StatelessWidget {
  final int active;
  final Set<int> done;
  final bool failed;
  final bool faceRequired;
  final String? gpsDetail;
  const _StepChecklist({
    required this.active,
    required this.done,
    required this.failed,
    required this.faceRequired,
    this.gpsDetail,
  });
  @override
  Widget build(BuildContext context) {
    final labels = [
      'Kiểm tra vị trí GPS',
      'Quét QR văn phòng',
      faceRequired
          ? 'Xác thực khuôn mặt'
          : 'Khuôn mặt (bỏ qua nếu chưa đăng ký)',
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
                    width: 24,
                    height: 24,
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
                : i == 1 && done.contains(1)
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
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
          if (onAccount != null)
            TextButton(onPressed: onAccount, child: const Text('Mở Tài khoản')),
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
          // editForm closes its own dialog before this route is closed.
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
