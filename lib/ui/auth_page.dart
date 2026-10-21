import 'package:flutter/material.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'common.dart';

class AuthPage extends StatefulWidget {
  final AppController controller;
  const AuthPage({super.key, required this.controller});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  final otp = TextEditingController();

  bool busy = false;
  bool otpStep = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> register() => editForm(
        context,
        title: 'Đăng ký tài khoản nhân viên',
        fields: {
          'Họ tên': '',
          'Email nhận OTP': '',
          'Tên đăng nhập': '',
          'Mật khẩu': '',
        },
        passwords: {'Mật khẩu'},
        save: (v) async {
          final email = v['Email nhận OTP']!;
          final uname = v['Tên đăng nhập']!;
          await widget.controller.register(
            Employee(
              id: newId(),
              name: v['Họ tên']!,
              email: email,
              username: uname,
              role: 'employee',
            ),
            v['Mật khẩu']!,
          );
          if (mounted) {
            _showVerifyEmailDialog(email, uname);
          }
        },
      );

  void _showVerifyEmailDialog(String email, String uname) {
    final verifyOtpCtrl = TextEditingController();
    bool verifying = false;
    String? dialogError;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Xác minh Email đăng ký'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hệ thống đã gửi mã OTP 6 số đến email: $email\nVui lòng kiểm tra hộp thư (kể cả mục Thư rác/Spam) và nhập mã bên dưới:',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: verifyOtpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Mã xác minh (6 số)',
                    errorText: dialogError,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: verifying
                    ? null
                    : () {
                        widget.controller.cancelOtpStep();
                        Navigator.pop(ctx);
                      },
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: verifying
                    ? null
                    : () async {
                        setDialogState(() {
                          verifying = true;
                          dialogError = null;
                        });
                        try {
                          await widget.controller
                              .verifyEmail(verifyOtpCtrl.text);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            setState(() {
                              username.text = uname;
                              otpStep = false;
                            });
                            message(
                              context,
                              'Xác minh thành công! Bạn có thể đăng nhập ngay.',
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            dialogError = e.toString();
                            verifying = false;
                          });
                        }
                      },
                child: verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Xác nhận'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFF087F8C),
                        child: Icon(
                          Icons.fingerprint,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Một ngày làm việc.\nBắt đầu đúng giờ.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'CHẤM CÔNG  /  TỐNG NHẬT BẢO AN',
                      style: TextStyle(
                        letterSpacing: 1.1,
                        color: Color(0xFF087F8C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      color: const Color(0xFFE8F5E9),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_done_outlined,
                              color: Color(0xFF2E7D32),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'MÁY CHỦ • ĐÃ KẾT NỐI WEB API\nDữ liệu thật lưu trên PostgreSQL. Mã OTP bảo mật gửi qua Email.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!otpStep) ...[
                      TextField(
                        controller: username,
                        decoration: const InputDecoration(
                          labelText: 'Tên đăng nhập',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        autofillHints: const [AutofillHints.username],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Xác thực OTP 2 lớp',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mã OTP 6 số đã được gửi tới email của bạn. Vui lòng kiểm tra hộp thư (kể cả mục Thư rác/Spam). Mã có hiệu lực 5 phút.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Mã OTP (6 chữ số)',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                if (otpStep) {
                                  await widget.controller.verifyOtp(otp.text);
                                } else {
                                  await widget.controller.beginLogin(
                                    username.text,
                                    password.text,
                                  );
                                  if (mounted) {
                                    setState(() => otpStep = true);
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = e.toString());
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: Text(
                        busy
                            ? 'Đang kết nối máy chủ…'
                            : otpStep
                                ? 'Xác nhận OTP & Đăng nhập'
                                : 'Tiếp tục nhận OTP',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (otpStep) {
                                setState(() {
                                  otpStep = false;
                                  error = null;
                                  otp.clear();
                                });
                                widget.controller.cancelOtpStep();
                              } else {
                                register();
                              }
                            },
                      child: Text(
                        otpStep
                            ? '← Quay lại nhập mật khẩu'
                            : 'Chưa có tài khoản? Đăng ký nhân viên mới',
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Nhóm 09 • Lập trình di động\nTống Nhật Bảo An',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
