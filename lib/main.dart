import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'domain/app_controller.dart';
import 'session_storage.dart';
import 'ui/auth_page.dart';
import 'ui/home_page.dart';
import 'ui/biometric_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AttendanceApp(controller: AppController.createDefault()));
}

class AttendanceApp extends StatefulWidget {
  final AppController controller;
  const AttendanceApp({super.key, required this.controller});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  bool _isChecking = true;
  String? _splashError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 2, 3 & 8. Khởi động ứng dụng, kiểm tra phiên đăng nhập và sinh trắc học
  Future<void> _bootstrap() async {
    setState(() {
      _isChecking = true;
      _splashError = null;
    });

    try {
      await widget.controller.client.init();

      // 2. Kiểm tra token có tồn tại và còn hạn hay không
      final isValidSession = await SessionStorage.isSessionValid();
      if (!isValidSession) {
        // Hết hạn hoặc không bật ghi nhớ đăng nhập -> xóa token và về màn đăng nhập
        await SessionStorage.clearSession();
        await widget.controller.client.clearTokens();
        if (mounted) setState(() => _isChecking = false);
        return;
      }

      // 3. Nếu người dùng đã kích hoạt sinh trắc học trên máy -> bắt buộc quét trước khi vào
      if (await BiometricLoginHelper.isEnabled) {
        final authed = await BiometricLoginHelper.authenticate();
        if (!authed) {
          // Thất bại hoặc hủy -> cho về màn đăng nhập bằng mật khẩu
          if (mounted) setState(() => _isChecking = false);
          return;
        }
      }

      // Kiểm tra nhanh với server để đồng bộ dữ liệu người dùng
      await widget.controller.load();

      if (widget.controller.user == null) {
        // Token bị server từ chối / hết hạn trên hệ thống
        await SessionStorage.clearSession();
        await widget.controller.client.clearTokens();
      }
    } catch (e) {
      // Lỗi mạng hoặc server không phản hồi -> nếu có token và user thì vẫn cho dùng offline
      if (widget.controller.user == null) {
        _splashError = 'Không thể xác thực phiên làm việc. Vui lòng kiểm tra kết nối mạng.';
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chấm công • Tống Nhật Bảo An',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.theme,
    // 8. Màn hình Splash trong lúc kiểm tra phiên, tránh nháy màn đăng nhập
    home: _isChecking
        ? const AppSplashScreen()
        : _splashError != null && widget.controller.user == null
        ? Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 54, color: Color(0xFFDC2626)),
                    const SizedBox(height: 12),
                    Text(
                      _splashError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _bootstrap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F7C8A),
                      ),
                      child: const Text('Thử lại'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _splashError = null),
                      child: const Text('Về màn Đăng nhập'),
                    ),
                  ],
                ),
              ),
            ),
          )
        : ListenableBuilder(
            listenable: widget.controller,
            builder: (_, _) => widget.controller.user == null
                ? AuthPage(controller: widget.controller)
                // 2. Vào thẳng màn chính HomePage, bên trong tự phân nhánh theo role
                : HomePage(controller: widget.controller),
          ),
  );
}

/// 8. Màn hình khởi động (Splash) hiển thị logo và tên ứng dụng
class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F7C8A).withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF0F7C8A),
                    child: const Icon(
                      Icons.access_time_filled_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'CHẤM CÔNG THÔNG MINH',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Đang kiểm tra phiên đăng nhập…',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0F7C8A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
