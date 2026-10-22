import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:share_plus/share_plus.dart';
import '../domain/app_controller.dart';
import 'biometric_page.dart';
import 'common.dart';
import 'home_page.dart' show acquirePosition;

class PunchPage extends StatefulWidget {
  final AppController controller;
  const PunchPage({super.key, required this.controller});
  @override
  State<PunchPage> createState() => _PunchPageState();
}

class _PunchPageState extends State<PunchPage> {
  Position? position;
  DateTime? capturedAt;
  String? qr;
  bool busy = false;
  String? error;
  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst("Exception: ", ""));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, office = c.data.office;
    final distance = position != null && office.configured
        ? Geolocator.distanceBetween(
            position!.latitude,
            position!.longitude,
            office.latitude!,
            office.longitude!,
          )
        : null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Section(
          title: c.openAttendance == null
              ? 'Bắt đầu ca làm'
              : 'Kết thúc ca làm',
          subtitle: office.configured
              ? '${office.name} • Phạm vi ${office.radius.round()} m'
              : 'Vui lòng nhờ Admin cấu hình văn phòng',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Lấy vị trí → Quét QR → Xác nhận giờ vào / ra'),
              const SizedBox(height: 8),
              const Text(
                'Xác thực sinh trắc học bổ sung khi bạn đã kích hoạt trong Tài khoản.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  position == null
                      ? Icons.location_searching
                      : Icons.location_on,
                  color: const Color(0xFF087F8C),
                ),
                title: Text(
                  position == null
                      ? 'Chưa lấy vị trí'
                      : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                ),
                subtitle: Text(
                  position == null
                      ? 'Chỉ thu thập khi bạn chủ động chấm công.'
                      : 'Sai số ±${position!.accuracy.round()} m${distance == null ? '' : ' • Cách văn phòng ${distance.round()} m'}',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final p = await acquirePosition();
                        if (mounted) {
                          setState(() {
                            position = p;
                            capturedAt = p.timestamp;
                          });
                        }
                      }),
                icon: const Icon(Icons.my_location),
                label: const Text('Lấy / cập nhật vị trí'),
              ),
              if (position != null)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final p = position!;
                          await SharePlus.instance.share(
                            ShareParams(
                              text:
                                  'Vị trí tôi chia sẻ lúc ${capturedAt!.toLocal()}: https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}\nSai số GPS ±${p.accuracy.round()} m.',
                            ),
                          );
                        }),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Chia sẻ vị trí qua ứng dụng khác'),
                ),
              const Divider(height: 30),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  qr == null
                      ? Icons.qr_code_scanner
                      : Icons.check_circle_outline,
                  color: const Color(0xFF087F8C),
                ),
                title: Text(
                  qr == null ? 'Chưa quét QR văn phòng' : 'Đã nhận mã QR',
                ),
                subtitle: const Text(
                  'Mã được kiểm tra lại khi xác nhận chấm công.',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final result = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ScannerPage(),
                          ),
                        );
                        if (mounted && result != null) {
                          setState(() => qr = result);
                        }
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Mở camera quét QR'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => editForm(
                        context,
                        title: 'Nhập mã QR thủ công',
                        fields: {'Mã QR': ''},
                        save: (v) async {
                          if (v.values.first.isEmpty) {
                            throw ArgumentError('Hãy nhập mã.');
                          }
                          setState(() => qr = v.values.first);
                        },
                      ),
                child: const Text('Nhập mã QR nếu camera không quét được'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    busy || position == null || qr == null || !office.configured
                    ? null
                    : () => run(() async {
                        if (await BiometricLoginHelper.isEnabled &&
                            !await BiometricLoginHelper.authenticate()) {
                          throw Exception(
                            'Xác thực sinh trắc học chưa thành công. Vui lòng thử lại.',
                          );
                        }
                        // Capture again after the device prompt, which may outlive the GPS freshness window.
                        final fresh = await acquirePosition();
                        if (!mounted) return;
                        setState(() {
                          position = fresh;
                          capturedAt = fresh.timestamp;
                        });
                        final checkingOut = c.openAttendance != null;
                        await c.punch(
                          qr: qr!,
                          latitude: position!.latitude,
                          longitude: position!.longitude,
                          accuracy: position!.accuracy,
                          distance: Geolocator.distanceBetween(
                            position!.latitude,
                            position!.longitude,
                            office.latitude!,
                            office.longitude!,
                          ),
                          capturedAt: capturedAt!,
                          mocked: position!.isMocked,
                        );
                        if (context.mounted) {
                          setState(() {
                            qr = null;
                            position = null;
                            capturedAt = null;
                          });
                          message(
                            context,
                            checkingOut
                                ? 'Đã ghi nhận giờ ra.'
                                : 'Đã ghi nhận giờ vào. Chúc bạn một ca làm tốt!',
                          );
                        }
                      }),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(
                  busy
                      ? 'Đang xử lý…'
                      : c.openAttendance == null
                      ? 'Xác nhận giờ vào'
                      : 'Xác nhận giờ ra',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool returned = false;
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
              if (value != null && !returned) {
                returned = true;
                Navigator.pop(context, value);
              }
            },
          ),
        ),
      ],
    ),
  );
}
