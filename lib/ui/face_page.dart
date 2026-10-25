import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'face_camera_page.dart';
import '../data/face_service.dart';
import '../domain/app_controller.dart';
import 'common.dart';

/// Capture through the live in-app front camera, never a gallery picker.
Future<String?> captureFace(BuildContext context, String title) =>
    showFaceCamera<String>(
      context,
      title: title,
      onCapture: (image) async => image,
    );

Future<String?> _enterCode(BuildContext context, {String? email}) async {
  String code = '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('Xác nhận bằng OTP email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              email == null || email.isEmpty
                  ? 'Nhập mã vừa gửi đến email đã đăng ký của tài khoản. Mã đăng nhập cũ không dùng được ở bước này.'
                  : 'Nhập mã vừa gửi đến $email. Kiểm tra cả hộp thư Spam/Quảng cáo. Mã đăng nhập cũ không dùng được ở bước này.',
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => update(() => code = v),
              decoration: const InputDecoration(labelText: 'OTP 6 số'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: code.length != 6 ? null : () => Navigator.pop(ctx, code),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ),
  );
}

class FaceSettingsCard extends StatefulWidget {
  final AppController controller;
  const FaceSettingsCard({super.key, required this.controller});
  @override
  State<FaceSettingsCard> createState() => _FaceSettingsCardState();
}

class _FaceSettingsCardState extends State<FaceSettingsCard> {
  late final service = FaceService(widget.controller.client);
  bool? enrolled;
  bool busy = false;
  bool allowLogin = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await service.statusInfo();
      if (mounted) {
        setState(() {
          enrolled = status.enrolled;
          allowLogin = status.enrolled ? status.allowLogin : true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _change({bool remove = false}) async {
    if (busy) return;
    final agreed = await confirm(
      context,
      remove
          ? 'Xóa mẫu khuôn mặt của bạn? Bạn sẽ trở về chấm công bằng GPS + QR. Cần OTP email để xác nhận.'
          : 'Đăng ký mẫu khuôn mặt cho tài khoản ${widget.controller.user?.username}? Hai ảnh sẽ gửi đến máy chủ của ứng dụng để tạo mẫu mã hóa; không lưu ảnh gốc trên server. Khi đã bật, chấm vào và ra đều cần khuôn mặt khớp. ${allowLogin ? 'Mẫu cũng được dùng cho đăng nhập bằng camera + OTP email.' : 'Không dùng mẫu để đăng nhập.'} Bạn đồng ý xử lý mẫu khuôn mặt?',
    );
    if (!agreed || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final started = await service.requestOtp();
      if (!mounted) return;
      String? first, second;
      if (!remove) {
        first = await captureFace(context, 'Đăng ký khuôn mặt — ảnh 1/2');
        if (first == null || !mounted) return;
        second = await captureFace(context, 'Đăng ký khuôn mặt — ảnh 2/2');
        if (second == null || !mounted) return;
      }
      final code = await _enterCode(
        context,
        email: started.email ?? widget.controller.user?.email,
      );
      if (code == null) return;
      if (remove) {
        await service.remove(started.challengeId, code);
      } else {
        await service.enroll(
          started.challengeId,
          code,
          first!,
          second!,
          allowLogin: allowLogin,
        );
      }
      if (mounted) {
        await _load();
        if (mounted) {
          message(
            context,
            remove
                ? 'Đã xóa mẫu khuôn mặt.'
                : 'Đã đăng ký. Chấm công vào/ra sẽ xác thực bằng khuôn mặt.',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Section(
    title: 'Xác thực khuôn mặt',
    subtitle: 'Nhận diện khuôn mặt khi chấm công và đăng nhập nhanh',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F7C8A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.face_retouching_natural, color: Color(0xFF0F7C8A), size: 22),
          ),
          title: Text(
            enrolled == null
                ? 'Đang kiểm tra...'
                : enrolled!
                ? 'Đã đăng ký khuôn mặt'
                : 'Chưa đăng ký khuôn mặt',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            enrolled == true
                ? 'Dữ liệu khuôn mặt đã được bảo mật để xác thực khi vào/ra ca.'
                : 'Đăng ký khuôn mặt để bắt đầu chấm công vào và ra ca.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
        if (enrolled != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đăng nhập bằng camera khuôn mặt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Xác thực khuôn mặt + OTP để đăng nhập vào ứng dụng.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            value: allowLogin,
            onChanged: busy
                ? null
                : (value) => setState(() => allowLogin = value),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (enrolled == null)
          OutlinedButton(
            onPressed: busy ? null : _load,
            child: const Text('Tải trạng thái'),
          )
        else ...[
          FilledButton.icon(
            onPressed: busy ? null : () => _change(),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              enrolled! ? 'Đăng ký lại mẫu (cần OTP)' : 'Đăng ký khuôn mặt',
            ),
          ),
          if (enrolled!)
            TextButton(
              onPressed: busy ? null : () => _change(remove: true),
              child: const Text('Xóa mẫu khuôn mặt (cần OTP)'),
            ),
        ],
      ],
    ),
  );
}
