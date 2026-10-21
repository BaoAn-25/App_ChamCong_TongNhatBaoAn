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
  final username = TextEditingController(),
      password = TextEditingController(),
      otp = TextEditingController();
  bool busy = false, otpStep = false, obscure = true;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> register(bool bootstrap) => editForm(
    context,
    title: bootstrap ? 'Khởi tạo Admin trên máy này' : 'Đăng ký nhân viên',
    fields: {'Họ tên': '', 'Email': '', 'Tên đăng nhập': '', 'Mật khẩu': ''},
    passwords: {'Mật khẩu'},
    save: (v) async {
      await widget.controller.register(
        Employee(
          id: newId(),
          name: v['Họ tên']!,
          email: v['Email']!,
          username: v['Tên đăng nhập']!,
          role: bootstrap ? 'admin' : 'employee',
        ),
        v['Mật khẩu']!,
        bootstrap: bootstrap,
      );
      if (mounted) {
        setState(() {
          username.text = v['Tên đăng nhập']!;
          otpStep = false;
        });
        message(
          context,
          'Đã tạo tài khoản local. Email chưa được xác minh qua server.',
        );
      }
    },
  );
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
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
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
                const Card(
                  color: Color(0xFFFFEFCF),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'BẢN LOCAL • CHƯA KẾT NỐI WEB API\nEmail chưa gửi thật. OTP hiển thị để thử luồng. Dữ liệu riêng trên từng thiết bị.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.controller.data.employees.isEmpty) ...[
                  const Text(
                    'Bắt đầu bằng cách tạo quản trị viên, sau đó cấu hình văn phòng, ca làm và nhân viên.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => register(true),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Thiết lập lần đầu'),
                  ),
                ] else ...[
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
                    Text(
                      'OTP thử nghiệm: ${widget.controller.demoOtp ?? 'Hết hiệu lực'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Có hiệu lực 2 phút, tối đa 5 lần nhập sai. Đây chưa phải xác thực email thật.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: otp,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'Mã OTP'),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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
                                widget.controller.verifyOtp(otp.text);
                              } else {
                                await widget.controller.beginLogin(
                                  username.text,
                                  password.text,
                                );
                                if (mounted) setState(() => otpStep = true);
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: Text(
                      busy
                          ? 'Đang xử lý…'
                          : otpStep
                          ? 'Xác nhận đăng nhập'
                          : 'Tiếp tục với OTP',
                    ),
                  ),
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
                            } else {
                              register(false);
                            }
                          },
                    child: Text(
                      otpStep
                          ? 'Quay lại đăng nhập'
                          : 'Chưa có tài khoản? Đăng ký bằng email',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Nhóm 09 • Lập trình di động',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
