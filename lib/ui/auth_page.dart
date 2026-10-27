import 'package:local_auth/local_auth.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../session_storage.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'biometric_page.dart';
import 'face_camera_page.dart';
import 'common.dart';

// ============================================================================
// 1. BẢNG MÀU & STYLE DÙNG CHUNG (THEME THEO MOCKUP CHUẨN)
// ============================================================================
class AuthColors {
  // Màu xanh Navy cho Header
  static const Color navy = Color(0xFF0A2234);
  static const Color navyLight = Color(0xFF13334C);

  // Màu Teal ngọc thương hiệu (Primary)
  static const Color primary = Color(0xFF006766);
  static const Color primaryDark = Color(0xFF004D40);
  static const Color primaryLight = Color(0xFFE6F3F3);
  static const Color primaryFocusBorder = Color(0xFF006766);

  // Nền trang
  static const Color scaffoldBg = Color(0xFFF4F7FB);

  // Màu viền và nền ô nhập
  static const Color inputBorder = Color(0xFFE2E8F0);
  static const Color inputFill = Color(0xFFF8FAFC);
  static const Color inputBorderError = Color(0xFFDC2626);

  // Màu chữ & icon
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color iconColor = Color(0xFF64748B);
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

  // Controller & FocusNode cho OTP
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  // Timer đếm ngược OTP
  Timer? _countdownTimer;
  int _resendCountdown = 60;
  bool _canResend = false;

  // Công tắc Ghi nhớ đăng nhập
  bool _rememberMe = true;

  bool _busy = false;
  bool _otpStep = false;
  bool _forgotStep = false;
  String _otpPurpose = 'login'; // 'login', 'register', hoặc 'reset-password'
  String? _targetEmail;
  String? _targetUsername;

  // Controllers cho Quên mật khẩu & Đặt lại mật khẩu
  final _forgotIdentifier = TextEditingController();
  final _resetNewPassword = TextEditingController();
  final _resetConfirmPassword = TextEditingController();
  bool _obscureResetPass = true;
  bool _obscureResetConfirmPass = true;

  bool _obscureLoginPass = true;
  bool _obscureRegPass = true;
  bool _obscureRegConfirmPass = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedUsername();
    _otpController.addListener(_onOtpChanged);
    _otpFocusNode.addListener(_onOtpChanged);
  }

  Future<void> _loadRememberedUsername() async {
    try {
      final last = await SessionStorage.getLastUsername();
      if (last != null && last.isNotEmpty && mounted) {
        setState(() {
          if (_loginUsername.text.isEmpty) {
            _loginUsername.text = last;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.removeListener(_onOtpChanged);
    _otpFocusNode.removeListener(_onOtpChanged);
    _otpController.dispose();
    _otpFocusNode.dispose();
    _loginUsername.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regUsername.dispose();
    _regPassword.dispose();
    _regConfirmPassword.dispose();
    _forgotIdentifier.dispose();
    _resetNewPassword.dispose();
    _resetConfirmPassword.dispose();
    super.dispose();
  }

  void _onOtpChanged() {
    if (mounted) setState(() {});
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
      _canResend = true;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
      }
    });
  }

  String _maskEmail(String email) {
    if (email.isEmpty) return 'email của bạn';
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) {
      return '$name***@$domain';
    }
    final prefix = name.substring(0, 2);
    return '$prefix***@$domain';
  }

  // LOGIC XỬ LÝ SINH TRẮC HỌC & ĐĂNG NHẬP
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
      final access = widget.controller.client.accessToken ?? await SessionStorage.getAccessToken() ?? '';
      await SessionStorage.saveSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        rememberMe: true,
      );
      if (widget.controller.user?.username != null) {
        final deviceId = await SessionStorage.getDeviceId();
        await SessionStorage.markDeviceTrusted(widget.controller.user!.username, deviceId);
        await SessionStorage.saveLastUsername(widget.controller.user!.username);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleFaceLogin() async {
    if (_busy) return;
    var username = _loginUsername.text.trim();
    if (username.isEmpty) {
      username = (await SessionStorage.getLastUsername()) ?? '';
      if (username.isNotEmpty) {
        _loginUsername.text = username;
      }
    }
    if (username.isEmpty) {
      setState(
        () => _error = 'Nhập tên đăng nhập trước khi quét khuôn mặt.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!mounted) return;
    try {
      final capturedBase64 = await showFaceCamera<String>(
        context,
        title: 'Đăng nhập bằng khuôn mặt',
        onCapture: (image) async => image,
      );
      if (capturedBase64 == null || !mounted) return;

      // Quét thành công -> Vào app trực tiếp không đòi OTP
      await widget.controller.loginWithFace(
        username: username,
        image: capturedBase64,
      );

      final refresh = widget.controller.client.refreshToken ?? '';
      final access = widget.controller.client.accessToken ?? await SessionStorage.getAccessToken() ?? '';
      await SessionStorage.saveSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        rememberMe: true,
      );
      final deviceId = await SessionStorage.getDeviceId();
      await SessionStorage.markDeviceTrusted(username, deviceId);
      await SessionStorage.saveLastUsername(username);
    } catch (e) {
      if (mounted) setState(() => _error = _cleanErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearErrors() {
    if (_error != null) setState(() => _error = null);
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
      final deviceId = await SessionStorage.getDeviceId();
      final isTrusted = await SessionStorage.isDeviceTrusted(uname, deviceId);
      final trustToken = await SessionStorage.getTrustToken(uname, deviceId);

      // Gửi đăng nhập kèm deviceId và trustToken nếu là máy quen thuộc
      await widget.controller.beginLogin(
        uname,
        pass,
        deviceId: deviceId,
        trustToken: isTrusted ? trustToken : null,
      );
      TextInput.finishAutofillContext(shouldSave: true);

      // Nếu hệ thống nhận diện máy quen thuộc và cho đăng nhập trực tiếp (không cần OTP)
      if (widget.controller.user != null) {
        final access = widget.controller.client.accessToken ?? await SessionStorage.getAccessToken() ?? '';
        final refresh = widget.controller.client.refreshToken ?? await SessionStorage.getRefreshToken() ?? '';
        await SessionStorage.saveSession(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          rememberMe: _rememberMe,
        );
        await SessionStorage.markDeviceTrusted(uname, deviceId);
        await SessionStorage.saveLastUsername(uname);
        if (mounted) {
          _checkAndPromptBiometrics();
        }
        return;
      }

      // Nếu là thiết bị mới hoặc chưa lưu trustToken -> chuyển sang màn hình nhập OTP
      if (mounted) {
        setState(() {
          _otpStep = true;
          _otpPurpose = 'login';
          _targetUsername = uname;
          _targetEmail = widget.controller.pendingEmail;
          _otpController.clear();
        });
        _startCountdownTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocusNode.requestFocus();
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
    final username = _regUsername.text.trim();
    final password = _regPassword.text;
    final confirm = _regConfirmPassword.text;

    if (name.isEmpty || email.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Vui lòng điền đầy đủ tất cả các trường.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Địa chỉ email không đúng định dạng.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Mật khẩu phải có độ dài tối thiểu 8 ký tự.');
      return;
    }
    if (password != confirm) {
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
        username: username,
        role: 'employee',
      );
      await widget.controller.register(newEmp, password);
      TextInput.finishAutofillContext(shouldSave: true);

      if (mounted) {
        setState(() {
          _otpStep = true;
          _otpPurpose = 'register';
          _targetUsername = username;
          _targetEmail = email;
          _otpController.clear();
        });
        _startCountdownTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocusNode.requestFocus();
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

    _countdownTimer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_otpPurpose == 'register') {
        final deviceId = await SessionStorage.getDeviceId();
        await widget.controller.verifyEmail(code, deviceId: deviceId);
        final uname = _targetUsername ?? _regUsername.text.trim();
        await SessionStorage.markDeviceTrusted(uname, deviceId);
        await SessionStorage.saveLastUsername(uname);

        // Nếu backend đã tự động cấp token đăng nhập thành công sau khi xác minh email
        if (widget.controller.user != null) {
          final access = widget.controller.client.accessToken ?? await SessionStorage.getAccessToken() ?? '';
          final refresh = widget.controller.client.refreshToken ?? await SessionStorage.getRefreshToken() ?? '';
          await SessionStorage.saveSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: DateTime.now().add(const Duration(days: 7)),
            rememberMe: true,
          );
          if (mounted) {
            _checkAndPromptBiometrics();
          }
          return;
        }

        if (mounted) {
          setState(() {
            _otpStep = false;
            _activeTab = 0;
            _loginUsername.text = uname;
            _loginPassword.clear();
            _otpController.clear();
            _error = null;
          });
          message(
            context,
            'Xác minh thành công! Mời bạn đăng nhập vào hệ thống.',
          );
        }
      } else if (_otpPurpose == 'reset-password') {
        final newPass = _resetNewPassword.text;
        final confirmPass = _resetConfirmPassword.text;
        if (newPass.length < 8) {
          setState(() => _error = 'Mật khẩu mới phải có ít nhất 8 ký tự.');
          return;
        }
        if (newPass != confirmPass) {
          setState(() => _error = 'Mật khẩu xác nhận không trùng khớp.');
          return;
        }
        await widget.controller.resetPassword(code: code, newPassword: newPass);
        if (mounted) {
          setState(() {
            _otpStep = false;
            _forgotStep = false;
            _activeTab = 0;
            _loginUsername.text = _targetUsername ?? '';
            _loginPassword.clear();
            _otpController.clear();
            _resetNewPassword.clear();
            _resetConfirmPassword.clear();
            _error = null;
          });
          message(
            context,
            'Đặt lại mật khẩu thành công! Hãy đăng nhập bằng mật khẩu mới.',
          );
        }
      } else {
        final deviceId = await SessionStorage.getDeviceId();
        await widget.controller.verifyOtp(code, deviceId: deviceId);

        final uname = _targetUsername ?? _loginUsername.text.trim();
        await SessionStorage.markDeviceTrusted(uname, deviceId);
        await SessionStorage.saveLastUsername(uname);

        final access = widget.controller.client.accessToken ?? await SessionStorage.getAccessToken() ?? '';
        final refresh = widget.controller.client.refreshToken ?? await SessionStorage.getRefreshToken() ?? '';
        await SessionStorage.saveSession(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          rememberMe: _rememberMe,
        );

        if (mounted) {
          _checkAndPromptBiometrics();
        }
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
      } else if (_otpPurpose == 'reset-password') {
        await widget.controller.requestPasswordReset(
          _targetUsername ?? _forgotIdentifier.text.trim(),
        );
      } else {
        await widget.controller.beginLogin(
          _targetUsername ?? _loginUsername.text.trim(),
          _loginPassword.text,
        );
      }
      if (mounted) {
        _otpController.clear();
        _startCountdownTimer();
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

  void _handleForgotPassword() {
    setState(() {
      _forgotStep = true;
      _otpStep = false;
      _error = null;
      _forgotIdentifier.text = _loginUsername.text.trim();
    });
  }

  Future<void> _handleSendResetOtp() async {
    final identifier = _forgotIdentifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên đăng nhập hoặc địa chỉ email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.controller.requestPasswordReset(identifier);
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) {
        setState(() {
          _forgotStep = false;
          _otpStep = true;
          _otpPurpose = 'reset-password';
          _targetUsername = identifier;
          _targetEmail = widget.controller.pendingEmail;
          _otpController.clear();
          _resetNewPassword.clear();
          _resetConfirmPassword.clear();
        });
        _startCountdownTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocusNode.requestFocus();
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

  // ============================================================================
  // GIAO DIỆN CHÍNH
  // ============================================================================
  Future<void> _checkAndPromptBiometrics() async {
    try {
      final supported = await BiometricLoginHelper.isDeviceSupported;
      final enrolled = await BiometricLoginHelper.isEnabled;
      if (supported && !enrolled && mounted) {
        final refresh = widget.controller.client.refreshToken;
        if (refresh != null) {
          final types = await BiometricLoginHelper.availableBiometrics;
          final isFace = types.contains(BiometricType.face);
          final label = isFace ? 'Face ID / Khuôn mặt' : 'Vân tay';
          if (!mounted) return;
          final shouldEnroll = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                    color: const Color(0xFF0F7C8A),
                  ),
                  const SizedBox(width: 10),
                  Text('Kích hoạt $label?'),
                ],
              ),
              content: Text(
                'Thiết bị hỗ trợ $label. Bạn có muốn kích hoạt để lần sau chỉ cần chạm/quét là vào ngay, không cần mật khẩu hay OTP?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Để sau', style: TextStyle(color: Color(0xFF64748B))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F7C8A)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Kích hoạt ngay'),
                ),
              ],
            ),
          );
          if (shouldEnroll == true) {
            final authed = await BiometricLoginHelper.authenticate();
            if (authed) {
              await BiometricLoginHelper.enroll(refresh);
            }
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.scaffoldBg,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            // Khối Header Navy ôm trọn Logo và Tiêu đề - Đảm bảo responsive trên mọi thiết bị
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AuthColors.navy,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, _otpStep ? 24 : 38),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _otpStep ? _buildOtpHeader() : _buildBrandHeader(),
                    ),
                  ),
                ),
              ),
            ),

            // Phần thân chứa Card Form trắng và Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      // Gối nhẹ Card Form lên mép cong Navy khi ở màn Đăng nhập, ở màn OTP giữ khoảng cách thoáng
                      Transform.translate(
                        offset: Offset(0, _otpStep ? 8 : -18),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 26,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: _otpStep
                                ? _buildOtpView()
                                : _forgotStep
                                    ? _buildForgotPasswordView()
                                    : _buildAuthFormsView(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header thương hiệu theo Mockup 1 (Logo giữ nguyên)
  Widget _buildBrandHeader() {
    return Column(
      children: [
        const SizedBox(height: 8),
        // Hộp chứa Logo bo góc 20px - GIỮ NGUYÊN LOGO
        Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: AuthColors.primary,
                child: const Icon(Icons.access_time_filled, color: Colors.white, size: 36),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Chấm Công Thông Minh',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Điểm danh và quản lý ca làm việc',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Header màn OTP theo Mockup 2
  Widget _buildOtpHeader() {
    return Row(
      children: [
        InkWell(
          onTap: _busy
              ? null
              : () {
                  setState(() {
                    _otpStep = false;
                    _forgotStep = false;
                    _error = null;
                    _otpController.clear();
                  });
                  widget.controller.cancelOtpStep();
                },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  // Form chuyển đổi giữa Đăng nhập và Đăng ký (Mockup 1)
  Widget _buildAuthFormsView() {
    return Column(
      key: const ValueKey('auth_forms'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab pill 2 tab Đăng nhập / Đăng ký
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabPill(
                  title: 'Đăng nhập',
                  index: 0,
                ),
              ),
              Expanded(
                child: _buildTabPill(
                  title: 'Đăng ký',
                  index: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        if (_activeTab == 0) _buildLoginForm() else _buildRegisterForm(),
      ],
    );
  }

  Widget _buildTabPill({required String title, required int index}) {
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? AuthColors.textPrimary : AuthColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // FORM ĐĂNG NHẬP (MOCKUP 1)
  // ============================================================================
  Widget _buildLoginForm() {
    return AutofillGroup(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          controller: _loginUsername,
          label: 'Tên đăng nhập',
          hint: 'Nhập tên tài khoản',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 16),

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

        // Ghi nhớ đăng nhập & Quên mật khẩu
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
              Expanded(
                child: GestureDetector(
                  onTap: _busy ? null : () => setState(() => _rememberMe = !_rememberMe),
                  child: const Text(
                    'Ghi nhớ đăng nhập',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AuthColors.textSecondary,
                    ),
                  ),
                ),
              ),
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
        const SizedBox(height: 18),

        // Nút Đăng nhập -> Gradient Teal ngọc
        Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AuthColors.primary, AuthColors.primaryDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AuthColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _busy ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),

        // Đường phân cách "HOẶC ĐĂNG NHẬP NHANH"
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'HOẶC ĐĂNG NHẬP NHANH',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
            ],
          ),
        ),

        // Hàng 2 nút bo tròn gọn gàng Khuôn mặt và Vân tay theo Mockup 1
        Row(
          children: [
            Expanded(
              child: _buildBiometricPillButton(
                icon: Icons.face_retouching_natural_rounded,
                label: 'Khuôn mặt',
                onPressed: _busy ? null : _handleFaceLogin,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBiometricPillButton(
                icon: Icons.fingerprint_rounded,
                label: 'Vân tay',
                onPressed: _busy ? null : _handleBiometricLogin,
              ),
            ),
          ],
        ),
      ],
    ),
  );
  }

  // Nút sinh trắc học bo tròn ngang chuẩn Mockup 1
  Widget _buildBiometricPillButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AuthColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AuthColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // FORM ĐĂNG KÝ
  // ============================================================================
  Widget _buildRegisterForm() {
    return AutofillGroup(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          controller: _regName,
          label: 'Họ và tên',
          hint: 'Ví dụ: Nguyễn Văn An',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regEmail,
          label: 'Email nhận mã OTP',
          hint: 'email@gmail.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regUsername,
          label: 'Tên đăng nhập',
          hint: 'nguyenvana',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

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
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regConfirmPassword,
          label: 'Xác nhận mật khẩu',
          hint: 'Nhập lại mật khẩu',
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

        Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AuthColors.primary, AuthColors.primaryDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AuthColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _busy ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    ),
  );
  }

  // ============================================================================
  // MÀN HÌNH XÁC THỰC OTP (MOCKUP 2)
  // ============================================================================
  Widget _buildOtpView() {
    final isRegister = _otpPurpose == 'register';
    final isReset = _otpPurpose == 'reset-password';
    final emailDisplay = _targetEmail ?? widget.controller.pendingEmail ?? '';

    return Column(
      key: const ValueKey('otp_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Icon phong bì thư tròn màu xanh teal
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AuthColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB2DFDB), width: 1.5),
            ),
            child: const Icon(
              Icons.mail_outline_rounded,
              color: AuthColors.primary,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 18),

        Text(
          isRegister
              ? 'Xác minh Email đăng ký'
              : isReset
                  ? 'Đặt lại mật khẩu'
                  : 'Xác thực OTP',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AuthColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          isRegister
              ? 'Mã OTP gồm 6 số đã được gửi đến email:'
              : 'Nhập mã 6 chữ số đã gửi tới:',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: AuthColors.textSecondary),
        ),
        const SizedBox(height: 4),

        Text(
          _maskEmail(emailDisplay),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AuthColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),

        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // 6 ô nhập mã OTP tách rời
        _buildOtpBoxes(),
        const SizedBox(height: 20),

        // Trường nhập mật khẩu mới nếu quên mật khẩu
        if (isReset) ...[
          _buildInputField(
            controller: _resetNewPassword,
            label: 'Mật khẩu mới (tối thiểu 8 ký tự)',
            hint: 'Nhập mật khẩu mới',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscureResetPass,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureResetPass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthColors.iconColor,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureResetPass = !_obscureResetPass),
            ),
          ),
          const SizedBox(height: 14),
          _buildInputField(
            controller: _resetConfirmPassword,
            label: 'Xác nhận mật khẩu mới',
            hint: 'Nhập lại mật khẩu mới',
            icon: Icons.lock_reset_rounded,
            obscureText: _obscureResetConfirmPass,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureResetConfirmPass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthColors.iconColor,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureResetConfirmPass = !_obscureResetConfirmPass),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Đếm ngược gửi lại mã OTP
        Center(
          child: TextButton.icon(
            onPressed: (_canResend && !_busy) ? _handleResendOtp : null,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              _canResend
                  ? 'Gửi lại mã OTP'
                  : 'Gửi lại mã sau 00:${_resendCountdown.toString().padLeft(2, '0')}',
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              foregroundColor: AuthColors.primary,
              disabledForegroundColor: const Color(0xFF64748B),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Nút Xác nhận Gradient Teal ngọc
        Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AuthColors.primary, AuthColors.primaryDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AuthColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _busy ? null : _handleVerifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
                        : isReset
                            ? 'Xác nhận & Đổi mật khẩu'
                            : 'Xác nhận',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),

        // Box an toàn thông báo theo Mockup 2: icon khiên bảo vệ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: Color(0xFF16A34A),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mã có hiệu lực trong 5 phút. Vui lòng không chia sẻ mã này cho bất kỳ ai.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF15803D),
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Nút Text: "Đổi tài khoản khác"
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _otpStep = false;
                      _forgotStep = false;
                      _error = null;
                      _otpController.clear();
                    });
                    widget.controller.cancelOtpStep();
                  },
            style: TextButton.styleFrom(
              foregroundColor: AuthColors.textSecondary,
            ),
            child: const Text(
              'Đổi tài khoản khác',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // 6 ô OTP riêng biệt theo Mockup chuẩn, không bị overlay xám hay Autofill che khuất
  Widget _buildOtpBoxes() {
    final text = _otpController.text;
    final hasFocus = _otpFocusNode.hasFocus;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Hàng 6 ô vuông OTP rõ ràng, sạch đẹp 100%
        IgnorePointer(
          child: Row(
            children: List.generate(6, (index) {
              final hasChar = index < text.length;
              final char = hasChar ? text[index] : '';
              final isCurrent = hasFocus && (index == text.length || (text.length == 6 && index == 5));

              Color borderColor;
              Color bgColor;
              double borderWidth = 1.4;
              List<BoxShadow> shadows = [];

              if (_error != null) {
                borderColor = AuthColors.inputBorderError;
                bgColor = const Color(0xFFFEF2F2);
              } else if (isCurrent) {
                borderColor = AuthColors.primary;
                borderWidth = 2.0;
                bgColor = Colors.white;
                shadows = [
                  BoxShadow(
                    color: AuthColors.primary.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ];
              } else if (hasChar) {
                borderColor = AuthColors.primary.withValues(alpha: 0.7);
                bgColor = AuthColors.primaryLight.withValues(alpha: 0.4);
              } else {
                borderColor = const Color(0xFFE2E8F0);
                bgColor = const Color(0xFFF8FAFC);
              }

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 3.5,
                    right: index == 5 ? 0 : 3.5,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 56,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor, width: borderWidth),
                      boxShadow: shadows,
                    ),
                    alignment: Alignment.center,
                    child: hasChar
                        ? Text(
                            char,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AuthColors.textPrimary,
                            ),
                          )
                        : isCurrent
                            ? Container(
                                width: 2.2,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: AuthColors.primary,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              )
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                  ),
                ),
              );
            }),
          ),
        ),

        // TextField trong suốt bao phủ toàn bộ vùng 6 ô để hứng thao tác bấm & bàn phím số
        Positioned.fill(
          child: Opacity(
            opacity: 0.0,
            child: TextField(
              controller: _otpController,
              focusNode: _otpFocusNode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              showCursor: false,
              enableInteractiveSelection: false,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              autofillHints: null,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              cursorColor: Colors.transparent,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) {
                _clearErrors();
                setState(() {});
                if (val.length == 6 && _otpPurpose != 'reset-password') {
                  _handleVerifyOtp();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // Giao diện Quên mật khẩu
  Widget _buildForgotPasswordView() {
    return Column(
      key: const ValueKey('forgot_password_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AuthColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB2DFDB), width: 1.5),
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: AuthColors.primary,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Quên mật khẩu?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AuthColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Nhập tên đăng nhập hoặc email tài khoản. Hệ thống sẽ gửi mã OTP xác thực để tạo mật khẩu mới.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AuthColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),

        if (_error != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        _buildInputField(
          controller: _forgotIdentifier,
          label: 'Tên đăng nhập hoặc Email',
          hint: 'Ví dụ: nguyenvana hoặc an@gmail.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),

        Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AuthColors.primary, AuthColors.primaryDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AuthColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _busy ? null : _handleSendResetOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
                      Icon(Icons.send_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Gửi mã OTP xác thực',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),

        Center(
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _forgotStep = false;
                      _error = null;
                    });
                  },
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Quay lại Đăng nhập'),
            style: TextButton.styleFrom(
              foregroundColor: AuthColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

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
        fillColor: AuthColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuthColors.primaryFocusBorder, width: 1.8),
        ),
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
          'Lập trình di động • Nhóm 09',
          style: TextStyle(
            fontSize: 12.5,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Tống Nhật Bảo An',
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
