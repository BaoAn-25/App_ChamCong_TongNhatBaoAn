import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../session_storage.dart';
import '../data/api_client.dart';
import '../data/api_repositories.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'biometric_page.dart';
import 'face_camera_page.dart';
import 'common.dart';

// ============================================================================
// 1. BẢNG MÀU & STYLE DÙNG CHUNG (THEME CONSTANTS)
// ============================================================================
class AuthColors {
  // Màu nhấn chủ đạo (Teal đồng nhất toàn bộ màn hình)
  static const Color primary = Color(0xFF0F7C8A);
  static const Color primaryDark = Color(0xFF0B5D68);
  static const Color primaryLight = Color(0xFFE6F4F6);
  static const Color primaryFocusBorder = Color(0xFF0F7C8A);

  // Màu viền và nền ô nhập
  static const Color inputBorder = Color(0xFFCBD5E1); // Viền xám trung tính rõ nét
  static const Color inputFill = Color(0xFFF8FAFC);   // Nền đồng nhất cho mọi ô
  static const Color inputBorderError = Color(0xFFDC2626); // Viền đỏ khi lỗi

  // Màu chữ & icon đủ độ tương phản
  static const Color textPrimary = Color(0xFF1E293B);   // Tiêu đề & nội dung chính
  static const Color textSecondary = Color(0xFF475569); // Chữ phụ, hướng dẫn
  static const Color textMuted = Color(0xFF64748B);     // Placeholder, helper
  static const Color iconColor = Color(0xFF64748B);     // Bộ icon nét đồng nhất
  static const Color error = Color(0xFFDC2626);
}

class AuthPage extends StatefulWidget {
  final AppController controller;
  const AuthPage({super.key, required this.controller});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // Tabs: 0 = Đăng nhập, 1 = Đăng ký
  int _activeTab = 0;

  // Controllers cho Đăng nhập
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();

  // Controllers cho Đăng ký
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regUsername = TextEditingController();
  final _regPassword = TextEditingController();
  final _regConfirmPassword = TextEditingController();

  // Controller cho OTP
  final _otpController = TextEditingController();

  // 6. Công tắc Ghi nhớ đăng nhập (mặc định bật)
  bool _rememberMe = true;

  bool _busy = false;
  bool _otpStep = false;
  bool _faceLoginFlow = false;
  String _otpPurpose = 'login'; // 'login' hoặc 'register'
  String? _targetEmail;
  String? _targetUsername;

  bool _obscureLoginPass = true;
  bool _obscureRegPass = true;
  bool _obscureRegConfirmPass = true;
  String? _error;

  // GIỮ NGUYÊN TOÀN BỘ LOGIC XỬ LÝ KHÔNG ĐỔI
  Future<void> _handleBiometricLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!await BiometricLoginHelper.isEnabled) {
        if (mounted) {
          setState(() {
            _error =
                'Bạn chưa bật đăng nhập sinh trắc học. Hãy đăng nhập bằng mật khẩu + OTP, sau đó vào Tài khoản và bấm Kích hoạt sinh trắc học.';
          });
        }
        return;
      }

      final authed = await BiometricLoginHelper.authenticate();
      if (!authed) {
        if (mounted) {
          setState(() {
            _error = 'Xác thực sinh trắc học không thành công hoặc đã bị hủy.';
          });
        }
        return;
      }

      final refresh = await BiometricLoginHelper.getRefreshToken();
      if (refresh == null) {
        await BiometricLoginHelper.unenroll();
        if (mounted) {
          setState(() {
            _error =
                'Không tìm thấy phiên đã lưu. Hãy đăng nhập bằng mật khẩu + OTP rồi bật lại sinh trắc học.';
          });
        }
        return;
      }

      await widget.controller.loginWithRefreshToken(refresh);
      final access = await SessionStorage.getAccessToken() ?? '';
      await SessionStorage.saveSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        rememberMe: true,
      );
    } catch (e) {
      final expired =
          e is ApiException && (e.statusCode == 400 || e.statusCode == 401);
      if (expired) await BiometricLoginHelper.unenroll();
      if (mounted) {
        setState(() {
          _error = expired
              ? 'Phiên sinh trắc học đã hết hạn. Hãy đăng nhập bằng mật khẩu + OTP rồi bật lại sinh trắc học.'
              : _cleanErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleFaceLogin() async {
    if (_busy) return;
    final username = _loginUsername.text.trim();
    if (username.isEmpty) {
      setState(
        () => _error = 'Nhập tên đăng nhập trước khi mở camera khuôn mặt.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final started = await showFaceCamera<OtpChallengeStart>(
        context,
        title: 'Đăng nhập bằng khuôn mặt',
        onCapture: (image) =>
            widget.controller.auth.faceLogin(username: username, image: image),
      );
      if (started == null || !mounted) return;
      widget.controller.stageFaceLogin(username, started);
      setState(() {
        _faceLoginFlow = true;
        _otpStep = true;
        _otpPurpose = 'login';
        _targetUsername = username;
        _targetEmail = started.email;
        _otpController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _cleanErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _loginUsername.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regUsername.dispose();
    _regPassword.dispose();
    _regConfirmPassword.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Future<void> _handleLogin() async {
    final uname = _loginUsername.text.trim();
    final pass = _loginPassword.text;
    if (uname.isEmpty || pass.isEmpty) {
      setState(
        () => _error = 'Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 4 & 5. Kiểm tra nếu thiết bị đã là thiết bị tin cậy
      final deviceId = await SessionStorage.getDeviceId();
      final isTrusted = await SessionStorage.isDeviceTrusted(uname, deviceId);

      // Nếu thiết bị đã tin cậy và có phiên refresh token hợp lệ -> vào thẳng, bỏ qua OTP
      if (isTrusted && widget.controller.client.hasTokens) {
        try {
          final refresh = widget.controller.client.refreshToken;
          if (refresh != null) {
            await widget.controller.loginWithRefreshToken(refresh);
      final access = await SessionStorage.getAccessToken() ?? '';
      await SessionStorage.saveSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        rememberMe: true,
      );
            if (widget.controller.user != null) {
              final access = await SessionStorage.getAccessToken() ?? '';
              await SessionStorage.saveSession(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: DateTime.now().add(const Duration(days: 7)),
                rememberMe: _rememberMe,
              );
              return;
            }
          }
        } catch (_) {
          // Phiên đã hết hạn -> tiếp tục đăng nhập mật khẩu + xác minh thiết bị
        }
      }

      await widget.controller.beginLogin(uname, pass);
      if (mounted) {
        setState(() {
          _faceLoginFlow = false;
          _otpStep = true;
          _otpPurpose = 'login';
          _targetUsername = uname;
          _targetEmail = widget.controller.pendingEmail;
          _otpController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleRegister() async {
    final name = _regName.text.trim();
    final email = _regEmail.text.trim();
    final uname = _regUsername.text.trim();
    final pass = _regPassword.text;
    final confirmPass = _regConfirmPassword.text;

    if (name.isEmpty || email.isEmpty || uname.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Vui lòng điền đầy đủ các thông tin đăng ký.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Định dạng email không hợp lệ.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Mật khẩu phải có tối thiểu 8 ký tự.');
      return;
    }
    if (pass != confirmPass) {
      setState(() => _error = 'Mật khẩu xác nhận không trùng khớp.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final newEmp = Employee(
        id: newId(),
        name: name,
        email: email,
        username: uname,
        role: 'employee',
      );
      await widget.controller.register(newEmp, pass);
      if (mounted) {
        setState(() {
          _otpStep = true;
          _otpPurpose = 'register';
          _targetEmail = email;
          _targetUsername = uname;
          _otpController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Mã OTP phải gồm đúng 6 chữ số.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_otpPurpose == 'register') {
        await widget.controller.verifyEmail(code);
        if (mounted) {
          setState(() {
            _otpStep = false;
            _activeTab = 0;
            _loginUsername.text = _targetUsername ?? '';
            _loginPassword.clear();
            _otpController.clear();
            _error = null;
          });
          message(
            context,
            'Xác minh thành công! Mời bạn đăng nhập vào hệ thống.',
          );
        }
      } else {
        await widget.controller.verifyOtp(code);

        // 5. Sau khi xác minh OTP lần đầu thành công -> lưu deviceId vào danh sách thiết bị tin cậy
        final uname = _targetUsername ?? _loginUsername.text.trim();
        final deviceId = await SessionStorage.getDeviceId();
        await SessionStorage.markDeviceTrusted(uname, deviceId);

        // 1 & 6. Lưu token phiên và hạn dùng theo công tắc "Ghi nhớ đăng nhập"
        final refresh = widget.controller.client.refreshToken ?? '';
        final access = await SessionStorage.getAccessToken() ?? '';
        await SessionStorage.saveSession(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          rememberMe: _rememberMe,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleResendOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_otpPurpose == 'register') {
        final newEmp = Employee(
          id: newId(),
          name: _regName.text.trim(),
          email: _regEmail.text.trim(),
          username: _regUsername.text.trim(),
          role: 'employee',
        );
        await widget.controller.register(newEmp, _regPassword.text);
      } else if (_faceLoginFlow) {
        final username = _targetUsername ?? _loginUsername.text.trim();
        final started = await showFaceCamera<OtpChallengeStart>(
          context,
          title: 'Xác thực lại để nhận OTP mới',
          onCapture: (image) => widget.controller.auth.faceLogin(
            username: username,
            image: image,
          ),
        );
        if (started == null || !mounted) return;
        widget.controller.stageFaceLogin(username, started);
        _targetEmail = started.email;
      } else {
        await widget.controller.beginLogin(
          _loginUsername.text.trim(),
          _loginPassword.text,
        );
      }
      if (mounted) {
        _otpController.clear();
        message(context, 'Đã gửi lại mã OTP mới về email của bạn!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cleanErrorMessage(Object error) {
    return error.toString().replaceFirst(
      RegExp(r'^(Exception: |StateError: |Bad state: )'),
      '',
    );
  }

  // Dialog hướng dẫn Quên mật khẩu
  void _handleForgotPassword() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AuthColors.primary),
            SizedBox(width: 10),
            Text('Quên mật khẩu?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Để bảo mật tài khoản chấm công nhân viên, vui lòng liên hệ Bộ phận Nhân sự (HR) hoặc Quản trị viên hệ thống để được cấp lại mật khẩu mới.',
          style: TextStyle(color: AuthColors.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AuthColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // GIAO DIỆN CHÍNH
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  // 4. Logo & Brand Header cố định kích thước
                  _buildBrandHeader(),
                  const SizedBox(height: 20),

                  // Card Đăng nhập / Đăng ký
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AuthColors.primary.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _otpStep
                          ? _buildOtpView(theme)
                          : _buildAuthFormsView(theme),
                    ),
                  ),

                  const SizedBox(height: 24),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 4. Header & Logo: Giữ kích thước cố định 72x72, chip trạng thái đồng bộ Teal
  Widget _buildBrandHeader() {
    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AuthColors.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AuthColors.primary, AuthColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.access_time_filled_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'CHẤM CÔNG THÔNG MINH',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AuthColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hệ thống quản lý điểm danh & ca làm việc',
          style: TextStyle(
            fontSize: 13,
            color: AuthColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        // 1. Chip trạng thái đồng nhất màu teal
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AuthColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFB2E0E6), width: 1),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContainerDot(color: AuthColors.primary),
              SizedBox(width: 8),
              Text(
                'CỔNG NHÂN VIÊN • CHẤM CÔNG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AuthColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Khối Form chuyển đổi giữa Đăng nhập và Đăng ký
  Widget _buildAuthFormsView(ThemeData theme) {
    return Column(
      key: const ValueKey('auth_forms'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab Switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  title: 'Đăng nhập',
                  index: 0,
                  icon: Icons.login_rounded,
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  title: 'Đăng ký',
                  index: 1,
                  icon: Icons.person_add_alt_1_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Error Banner
        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // Nội dung theo Tab
        if (_activeTab == 0) _buildLoginForm() else _buildRegisterForm(),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required int index,
    required IconData icon,
  }) {
    final isSelected = _activeTab == index;
    return GestureDetector(
      onTap: () {
        if (_activeTab != index) {
          setState(() {
            _activeTab = index;
            _error = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? AuthColors.primary : AuthColors.iconColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AuthColors.textPrimary : AuthColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // FORM ĐĂNG NHẬP
  // ============================================================================
  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2. Ô Tên đăng nhập dùng style thống nhất
        _buildInputField(
          controller: _loginUsername,
          label: 'Tên đăng nhập',
          hint: 'Nhập tên tài khoản hoặc mã nhân viên',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 16),

        // 2. Ô Mật khẩu dùng style thống nhất
        _buildInputField(
          controller: _loginPassword,
          label: 'Mật khẩu',
          hint: 'Nhập mật khẩu',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureLoginPass,
          autofillHints: const [AutofillHints.password],
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscureLoginPass = !_obscureLoginPass),
            icon: Icon(
              _obscureLoginPass
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AuthColors.iconColor,
              size: 20,
            ),
          ),
        ),

        // 6. Công tắc "Ghi nhớ đăng nhập" (mặc định bật) và link "Quên mật khẩu?"
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: _rememberMe,
                  activeColor: AuthColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                  onChanged: _busy ? null : (v) => setState(() => _rememberMe = v ?? true),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _busy ? null : () => setState(() => _rememberMe = !_rememberMe),
                child: const Text(
                  'Ghi nhớ đăng nhập',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AuthColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _handleForgotPassword,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AuthColors.primary,
                ),
                child: const Text(
                  'Quên mật khẩu?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AuthColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3 & 5. Nút chính Teal đặc + Trạng thái loading
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AuthColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Đăng nhập',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),

        // 3. Đường ngăn cách "hoặc"
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'hoặc đăng nhập nhanh',
                  style: TextStyle(
                    fontSize: 12,
                    color: AuthColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
            ],
          ),
        ),

        // 3. Hai nút phụ cùng 1 kiểu (viền xám nhạt, chữ/icon teal)
        _buildSecondaryButton(
          title: 'Camera khuôn mặt + OTP',
          icon: Icons.camera_alt_outlined,
          onPressed: _busy ? null : _handleFaceLogin,
        ),
        const SizedBox(height: 10),
        _buildSecondaryButton(
          title: 'Sinh trắc của điện thoại',
          icon: Icons.fingerprint_rounded,
          onPressed: _busy ? null : _handleBiometricLogin,
        ),
      ],
    );
  }

  // ============================================================================
  // FORM ĐĂNG KÝ
  // ============================================================================
  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ô 1: Họ tên (cùng nền & style với các ô khác, không bị xám đậm)
        _buildInputField(
          controller: _regName,
          label: 'Họ và tên nhân viên',
          hint: 'Ví dụ: Nguyễn Văn An',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regEmail,
          label: 'Email nhận mã OTP',
          hint: 'Ví dụ: an.nguyen@gmail.com',
          icon: Icons.mail_outline_rounded,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regUsername,
          label: 'Tên đăng nhập',
          hint: 'Ví dụ: an_nv25',
          icon: Icons.account_circle_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        // Ô Mật khẩu + Gợi ý quy tắc mật khẩu
        _buildInputField(
          controller: _regPassword,
          label: 'Mật khẩu',
          hint: 'Tối thiểu 8 ký tự',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureRegPass,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscureRegPass = !_obscureRegPass),
            icon: Icon(
              _obscureRegPass
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AuthColors.iconColor,
              size: 20,
            ),
          ),
        ),
        // 5. Gợi ý quy tắc mật khẩu ở màn đăng ký
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 4),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AuthColors.textMuted),
              SizedBox(width: 6),
              Text(
                'Mật khẩu tối thiểu 8 ký tự (nên gồm chữ và số)',
                style: TextStyle(
                  fontSize: 12,
                  color: AuthColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regConfirmPassword,
          label: 'Xác nhận mật khẩu',
          hint: 'Nhập lại mật khẩu ở trên',
          icon: Icons.lock_reset_rounded,
          obscureText: _obscureRegConfirmPass,
          textInputAction: TextInputAction.done,
          suffixIcon: IconButton(
            onPressed: () => setState(
              () => _obscureRegConfirmPass = !_obscureRegConfirmPass,
            ),
            icon: Icon(
              _obscureRegConfirmPass
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AuthColors.iconColor,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 22),

        // 5. Nút Đăng ký + Trạng thái loading
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: AuthColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Đăng ký tài khoản',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.check_circle_outline_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // WIDGET HELPER: 2. STYLE Ô NHẬP LIỆU CHUẨN DÙNG CHUNG
  // ============================================================================
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: obscureText,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onChanged: (_) => _clearErrors(),
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AuthColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: AuthColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: AuthColors.primary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: AuthColors.iconColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AuthColors.inputFill, // Nền đồng nhất cho toàn bộ các ô
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        // Viền bình thường rõ hơn
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.inputBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.inputBorder, width: 1.2),
        ),
        // Viền Teal khi focus
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.primaryFocusBorder, width: 1.8),
        ),
        // Viền Đỏ khi lỗi
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.inputBorderError, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.inputBorderError, width: 1.8),
        ),
      ),
    );
  }

  // 3. Widget nút phụ: viền xám nhạt (inputBorder), chữ và icon Teal đồng nhất
  Widget _buildSecondaryButton({
    required String title,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: AuthColors.primary),
      label: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AuthColors.primary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: const BorderSide(color: AuthColors.inputBorder, width: 1.2),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  // ============================================================================
  // MÀN HÌNH NHẬP MÃ OTP
  // ============================================================================
  Widget _buildOtpView(ThemeData theme) {
    final isRegister = _otpPurpose == 'register';

    return Column(
      key: const ValueKey('otp_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AuthColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: AuthColors.primary,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isRegister ? 'Xác minh Email đăng ký' : 'Xác thực OTP 2 bước',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AuthColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isRegister
              ? 'Mã OTP gồm 6 số đã được gửi đến email:'
              : _faceLoginFlow
              ? 'Khuôn mặt khớp. Mã OTP 6 số đã gửi đến email đăng ký của tài khoản này:'
              : 'Vui lòng nhập mã OTP 6 số gửi đến email đã đăng ký của tài khoản:',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AuthColors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (_targetEmail != null && _targetEmail!.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AuthColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _targetEmail!,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AuthColors.primary,
                ),
              ),
            ),
          )
        else if (_targetUsername != null && _targetUsername!.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AuthColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Tài khoản: $_targetUsername',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AuthColors.primary,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),

        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // Ô Nhập OTP
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AuthColors.inputFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _error != null
                  ? AuthColors.inputBorderError
                  : AuthColors.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            autofocus: true,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
              color: AuthColors.textPrimary,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: TextStyle(letterSpacing: 10, color: Color(0xFFCBD5E1)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (val) {
              _clearErrors();
              if (val.length == 6) {
                _handleVerifyOtp();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mã có hiệu lực trong 5 phút. Hãy kiểm tra cả hộp thư Spam.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AuthColors.textMuted),
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleVerifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AuthColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    isRegister
                        ? 'Xác nhận & Hoàn tất đăng ký'
                        : 'Xác nhận OTP & Vào ứng dụng',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _otpStep = false;
                        _error = null;
                        _otpController.clear();
                      });
                      widget.controller.cancelOtpStep();
                    },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Quay lại'),
              style: TextButton.styleFrom(
                foregroundColor: AuthColors.textSecondary,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _handleResendOtp,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Gửi lại mã OTP'),
              style: TextButton.styleFrom(
                foregroundColor: AuthColors.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Khối thông báo lỗi
  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AuthColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Text(
          'Lập trình di động',
          style: TextStyle(
            fontSize: 12,
            color: AuthColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Nhóm 09 — Tống Nhật Bảo An',
          style: TextStyle(
            fontSize: 12,
            color: AuthColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// Widget chấm tròn nhỏ cho chip trạng thái
class ContainerDot extends StatelessWidget {
  final Color color;
  const ContainerDot({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
