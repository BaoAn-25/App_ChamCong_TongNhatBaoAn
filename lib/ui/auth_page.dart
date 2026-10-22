import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/api_client.dart';
import '../data/api_repositories.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'biometric_page.dart';
import 'face_camera_page.dart';
import 'common.dart';

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

  /// Đăng nhập nhanh: sinh trắc học thay thế bước OTP.
  /// Khôi phục phiên bằng refresh token đã lưu sau khi xác thực thiết bị thành công.
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

  // Xử lý gửi Đăng nhập Bước 1
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

  // Xử lý gửi Đăng ký
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

  // Xử lý xác nhận mã OTP
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
        // Xác thực email đăng ký
        await widget.controller.verifyEmail(code);
        if (mounted) {
          setState(() {
            _otpStep = false;
            _activeTab = 0; // Chuyển về tab Đăng nhập
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
        // Xác thực OTP đăng nhập
        await widget.controller.verifyOtp(code);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Gửi lại mã OTP
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = const Color(0xFF087F8C);

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
                  // Logo & Brand Header
                  _buildBrandHeader(primaryColor),
                  const SizedBox(height: 20),

                  // Main Interactive Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF087F8C,
                          ).withValues(alpha: 0.08),
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
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _otpStep
                          ? _buildOtpView(primaryColor, theme)
                          : _buildAuthFormsView(primaryColor, theme),
                    ),
                  ),

                  const SizedBox(height: 24),
                  // Footer info
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Header thương hiệu chuyên nghiệp
  Widget _buildBrandHeader(Color primaryColor) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.28),
                blurRadius: 18,
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF087F8C), Color(0xFF034047)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.access_time_filled_rounded,
                    color: Colors.white,
                    size: 40,
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
            letterSpacing: 1.2,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hệ thống quản lý điểm danh & ca làm việc',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        // Live server indicator pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFA5D6A7), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'CHẤM CÔNG NHÂN VIÊN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B5E20),
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
  Widget _buildAuthFormsView(Color primaryColor, ThemeData theme) {
    return Column(
      key: const ValueKey('auth_forms'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab Switcher Hiện Đại (Đăng nhập / Đăng ký)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  title: 'Đăng nhập',
                  index: 0,
                  icon: Icons.login_rounded,
                  primaryColor: primaryColor,
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  title: 'Đăng ký',
                  index: 1,
                  icon: Icons.person_add_alt_1_rounded,
                  primaryColor: primaryColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Error Banner
        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // Nội dung theo Tab
        if (_activeTab == 0)
          _buildLoginForm(primaryColor)
        else
          _buildRegisterForm(primaryColor),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required int index,
    required IconData icon,
    required Color primaryColor,
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? primaryColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FORM ĐĂNG NHẬP
  Widget _buildLoginForm(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginUsername,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          enabled: !_busy,
          onChanged: (_) => _clearErrors(),
          decoration: InputDecoration(
            labelText: 'Tên đăng nhập',
            hintText: 'Nhập tên tài khoản hoặc mã nhân viên',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryColor, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPassword,
          autofillHints: const [AutofillHints.password],
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: _obscureLoginPass,
          onChanged: (_) => _clearErrors(),
          decoration: InputDecoration(
            labelText: 'Mật khẩu',
            hintText: 'Nhập mật khẩu',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureLoginPass = !_obscureLoginPass),
              icon: Icon(
                _obscureLoginPass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF94A3B8),
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryColor, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _handleFaceLogin,
          icon: const Icon(Icons.face_retouching_natural),
          label: const Text('Camera khuôn mặt + OTP'),
        ),
        const SizedBox(height: 8),
        // Native device biometrics remain a separate optional shortcut.
        OutlinedButton.icon(
          onPressed: _busy ? null : _handleBiometricLogin,
          icon: const Icon(Icons.fingerprint_rounded, size: 22),
          label: const Text('Sinh trắc của điện thoại'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: primaryColor,
            side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // FORM ĐĂNG KÝ
  Widget _buildRegisterForm(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _regName,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearErrors(),
          decoration: _inputDecoration(
            'Họ và tên nhân viên',
            'Ví dụ: Nguyễn Văn An',
            Icons.badge_outlined,
            primaryColor,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _regEmail,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _clearErrors(),
          decoration: _inputDecoration(
            'Email nhận mã OTP',
            'Ví dụ: an.nguyen@gmail.com',
            Icons.email_outlined,
            primaryColor,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _regUsername,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearErrors(),
          decoration: _inputDecoration(
            'Tên đăng nhập',
            'Ví dụ: an_nv25',
            Icons.account_circle_outlined,
            primaryColor,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _regPassword,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          obscureText: _obscureRegPass,
          onChanged: (_) => _clearErrors(),
          decoration: _inputDecoration(
            'Mật khẩu',
            'Tối thiểu 8 ký tự',
            Icons.lock_outline_rounded,
            primaryColor,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureRegPass = !_obscureRegPass),
              icon: Icon(
                _obscureRegPass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _regConfirmPassword,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          obscureText: _obscureRegConfirmPass,
          onChanged: (_) => _clearErrors(),
          decoration: _inputDecoration(
            'Xác nhận mật khẩu',
            'Nhập lại mật khẩu ở trên',
            Icons.lock_reset_rounded,
            primaryColor,
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _obscureRegConfirmPass = !_obscureRegConfirmPass,
              ),
              icon: Icon(
                _obscureRegConfirmPass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
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

  // MÀN HÌNH NHẬP MÃ OTP HIỆN ĐẠI
  Widget _buildOtpView(Color primaryColor, ThemeData theme) {
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
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              color: primaryColor,
              size: 32,
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
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isRegister
              ? 'Mã OTP gồm 6 số đã được gửi đến email:'
              : _faceLoginFlow
              ? 'Khuôn mặt khớp. Mã OTP 6 số đã gửi đến email đăng ký của tài khoản này (không gửi theo Gmail đang mở trên máy):'
              : 'Vui lòng nhập mã OTP 6 số gửi đến email đã đăng ký của tài khoản:',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 6),
        if (_targetEmail != null && _targetEmail!.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _targetEmail!,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
            ),
          )
        else if (_targetUsername != null && _targetUsername!.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Tài khoản: $_targetUsername',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),

        // Error Banner nếu có lỗi
        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // Ô Nhập OTP Định Dạng Số Lớn Sang Trọng
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _error != null
                  ? const Color(0xFFEF4444)
                  : primaryColor.withValues(alpha: 0.4),
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
              color: Color(0xFF0F172A),
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
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 24),

        // Nút Xác nhận
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _handleVerifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
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
                foregroundColor: const Color(0xFF64748B),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _handleResendOtp,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Gửi lại mã OTP'),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Khối hiển thị thông báo lỗi đẹp
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
            color: Color(0xFFDC2626),
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

  InputDecoration _inputDecoration(
    String label,
    String hint,
    IconData prefixIcon,
    Color primaryColor, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Text(
          'Đồ án môn học • Lập trình di động',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Nhóm 09 — Tống Nhật Bảo An',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
