import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_theme.dart';
import '../../data/face_service.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/biometric_page.dart';
import '../../ui/face_camera_page.dart';
import '../../widgets/app_widgets.dart';
import 'admin_management_dialogs.dart';

/// Màn hình Tài khoản đa vai trò (Nhân viên, Admin, Quản lý)
/// Thiết kế chuẩn theo giao diện 3 vai trò:
/// - Header Navy bo cong tràn viền: "Tài khoản" • "Hồ sơ và bảo mật" / "Hồ sơ, hệ thống và bảo mật"
/// - Profile Card: Avatar + camera badge, tên, chip vai trò (Nhân viên / Quản trị viên / Quản lý),
///   bảng thông tin (@username, email, phòng ban), nút sửa hồ sơ.
/// - Khối trung gian theo vai trò:
///   + Admin: "Quản trị hệ thống" (Nơi làm việc, Ca làm, Phòng ban)
///   + Quản lý: "Nhóm của tôi" (Thành viên, Đơn chờ duyệt, Đã chấm công)
/// - Khối "Bảo mật":
///   + Khuôn mặt (Đã đăng ký / Đăng ký lại)
///   + Đăng nhập bằng camera + OTP (dành cho Nhân viên)
///   + Vân tay của điện thoại (Toggle switch)
///   + Đổi mật khẩu (Cần xác nhận bằng OTP)
/// - Nút "Đăng xuất" nền đỏ nhạt (#FFF1F2)
/// - Footer: "Nhóm 09 • Phiên bản 1.0.0"
class AdminAccountScreen extends StatefulWidget {
  final AppController controller;
  final VoidCallback onLogout;
  final bool isTab;
  final VoidCallback? onNavigateToTimesheet;

  const AdminAccountScreen({
    super.key,
    required this.controller,
    required this.onLogout,
    this.isTab = false,
    this.onNavigateToTimesheet,
  });

  @override
  State<AdminAccountScreen> createState() => _AdminAccountScreenState();
}

class _AdminAccountScreenState extends State<AdminAccountScreen> {
  AppController get c => widget.controller;

  String? _avatarBase64;
  bool _isLocating = false;

  // Face status
  late final FaceService _faceService = FaceService(widget.controller.client);
  bool? _faceEnrolled;
  bool _faceBusy = false;
  bool _allowFaceLogin = true;

  // Biometric status
  bool _bioSupported = false;
  bool _bioEnrolled = false;
  bool _bioLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    _loadFaceStatus();
    _loadBiometricStatus();
    _loadFaceLoginPreference();
  }

  Future<void> _loadFaceLoginPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = c.user?.id;
      if (uid != null) {
        final val = prefs.getBool('allow_face_login_$uid') ?? true;
        if (mounted) setState(() => _allowFaceLogin = val);
      }
    } catch (_) {}
  }

  Future<void> _setFaceLoginPreference(bool val) async {
    setState(() => _allowFaceLogin = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = c.user?.id;
      if (uid != null) {
        await prefs.setBool('allow_face_login_$uid', val);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 1. AVATAR & HỒ SƠ
  // ---------------------------------------------------------------------------
  Future<void> _loadAvatar() async {
    final uid = c.user?.id;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString('user_avatar_$uid');
      if (mounted && b64 != _avatarBase64) {
        setState(() => _avatarBase64 = b64);
      }
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    final uid = c.user?.id;
    if (uid == null) return;

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Chọn ảnh đại diện',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.teal),
                title: const Text('Chụp ảnh từ camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.teal),
                title: const Text('Chọn ảnh từ thư viện'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_avatarBase64 != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  title: const Text('Xóa ảnh đại diện', style: TextStyle(color: AppColors.error)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_avatar_$uid');
                    if (mounted) setState(() => _avatarBase64 = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      final b64 = base64Encode(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_$uid', b64);
      if (mounted) {
        setState(() => _avatarBase64 = b64);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật ảnh: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Mở hộp thoại chỉnh sửa hồ sơ
  Future<void> _openEditProfileDialog() async {
    final user = c.user;
    if (user == null) return;

    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chỉnh sửa hồ sơ cá nhân',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập họ và tên' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email nhận mã OTP',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Vui lòng nhập email';
                      if (!v.contains('@')) return 'Email không hợp lệ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B1F3A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheetState(() => isSaving = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final nav = Navigator.of(ctx);
                              try {
                                final updated = Employee.fromJson(user.toJson())
                                  ..name = nameController.text.trim()
                                  ..email = emailController.text.trim();
                                await c.saveEmployee(updated);
                                if (mounted) {
                                  setState(() {});
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Đã cập nhật hồ sơ thành công!')),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Lưu thay đổi', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. KHUÔN MẶT
  // ---------------------------------------------------------------------------
  Future<void> _loadFaceStatus() async {
    try {
      final status = await _faceService.statusInfo();
      if (mounted) {
        setState(() {
          _faceEnrolled = status.enrolled;
        });
      }
    } catch (e) {
      // face error handled
    }
  }

  Future<String?> _enterOtpDialog({String? email}) async {
    String code = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Xác nhận bằng mã OTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email == null || email.isEmpty
                    ? 'Nhập mã 6 chữ số gửi đến email tài khoản của bạn.'
                    : 'Nhập mã 6 chữ số vừa gửi đến $email.',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => setDialogState(() => code = v),
                decoration: const InputDecoration(
                  labelText: 'Mã OTP 6 số',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              onPressed: code.length != 6 ? null : () => Navigator.pop(ctx, code),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFaceEnrollment({bool remove = false}) async {
    if (_faceBusy) return;

    final confirmAction = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(remove ? 'Xác nhận xóa khuôn mặt' : 'Đăng ký khuôn mặt'),
        content: Text(
          remove
              ? 'Bạn có chắc chắn muốn xóa mẫu khuôn mặt đã lưu? Cần xác thực OTP email để thực hiện.'
              : 'Hệ thống sẽ chụp 2 góc ảnh từ camera trước và yêu cầu xác thực OTP email để đăng ký mẫu khuôn mặt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          ElevatedButton(
            style: remove ? ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(remove ? 'Xóa mẫu' : 'Tiếp tục'),
          ),
        ],
      ),
    );

    if (confirmAction != true || !mounted) return;

    setState(() {
      _faceBusy = true;
    });

    try {
      final started = await _faceService.requestOtp();
      if (!mounted) return;

      String? first, second;
      if (!remove) {
        first = await showFaceCamera<String>(
          context,
          title: 'Đăng ký khuôn mặt — ảnh 1/2',
          onCapture: (img) async => img,
        );
        if (first == null || !mounted) return;

        second = await showFaceCamera<String>(
          context,
          title: 'Đăng ký khuôn mặt — ảnh 2/2',
          onCapture: (img) async => img,
        );
        if (second == null || !mounted) return;
      }

      final code = await _enterOtpDialog(email: started.email ?? c.user?.email);
      if (code == null) return;

      if (remove) {
        await _faceService.remove(started.challengeId, code);
      } else {
        await _faceService.enroll(
          started.challengeId,
          code,
          first!,
          second!,
          allowLogin: _allowFaceLogin,
        );
      }

      if (mounted) {
        await _loadFaceStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(remove ? 'Đã xóa mẫu khuôn mặt thành công.' : 'Đã đăng ký mẫu khuôn mặt thành công.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      // face error handled
    } finally {
      if (mounted) setState(() => _faceBusy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. SINH TRẮC HỌC (VÂN TAY)
  // ---------------------------------------------------------------------------
  Future<void> _loadBiometricStatus() async {
    final supported = await BiometricLoginHelper.isDeviceSupported;
    final enrolled = await BiometricLoginHelper.isEnabled;
    if (mounted) {
      setState(() {
        _bioSupported = supported;
        _bioEnrolled = enrolled;
        _bioLoading = false;
      });
    }
  }

  Future<void> _toggleBiometric() async {
    if (_bioEnrolled) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tắt đăng nhập sinh trắc'),
          content: const Text('Bạn có chắc chắn muốn tắt đăng nhập bằng sinh trắc học? Lần sau bạn sẽ cần nhập mật khẩu và OTP.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tắt'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await BiometricLoginHelper.unenroll();
      setState(() => _bioEnrolled = false);
    } else {
      final ok = await BiometricLoginHelper.authenticate();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Xác thực sinh trắc học thất bại.')),
          );
        }
        return;
      }
      final refresh = c.client.refreshToken ?? '';
      await BiometricLoginHelper.enroll(refresh);
      setState(() => _bioEnrolled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã kích hoạt đăng nhập sinh trắc học thành công!'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 4. ĐỔI MẬT KHẨU (XÁC THỰC BẰNG OTP)
  // ---------------------------------------------------------------------------
  Future<void> _openChangePasswordDialog() async {
    final user = c.user;
    if (user == null) return;

    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isOtpSent = false;
    bool isBusy = false;
    String? challengeId;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF006766).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF006766), size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Đổi mật khẩu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isOtpSent) ...[
                  const Text(
                    'Để đảm bảo an toàn thông tin, hệ thống sẽ gửi một mã OTP gồm 6 chữ số đến email của bạn để xác thực trước khi đổi mật khẩu.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 18, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            user.email,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    'Mã OTP đã được gửi đến ${user.email}. Vui lòng nhập mã và mật khẩu mới.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'Mã xác nhận OTP (6 số)',
                      counterText: '',
                      prefixIcon: const Icon(Icons.mark_email_read_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu mới (ít nhất 8 ký tự)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Nhập lại mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isBusy ? null : () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B1F3A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isBusy
                  ? null
                  : () async {
                      if (!isOtpSent) {
                        setDialogState(() {
                          isBusy = true;
                          errorText = null;
                        });
                        try {
                          final challenge = await c.auth.forgotPassword(user.email);
                          setDialogState(() {
                            challengeId = challenge.challengeId;
                            isOtpSent = true;
                            isBusy = false;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isBusy = false;
                            errorText = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      } else {
                        final code = otpCtrl.text.trim();
                        final newPass = newPassCtrl.text;
                        final confirmPass = confirmPassCtrl.text;
                        if (code.length != 6) {
                          setDialogState(() => errorText = 'Vui lòng nhập đủ 6 chữ số OTP.');
                          return;
                        }
                        if (newPass.length < 8) {
                          setDialogState(() => errorText = 'Mật khẩu mới phải có ít nhất 8 ký tự.');
                          return;
                        }
                        if (newPass != confirmPass) {
                          setDialogState(() => errorText = 'Mật khẩu xác nhận không trùng khớp.');
                          return;
                        }
                        setDialogState(() {
                          isBusy = true;
                          errorText = null;
                        });
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        try {
                          await c.auth.resetPassword(challengeId: challengeId!, code: code, newPassword: newPass);
                          if (mounted) {
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Đổi mật khẩu thành công!'),
                                backgroundColor: Color(0xFF16A34A),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isBusy = false;
                            errorText = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      }
                    },
              child: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isOtpSent ? 'Xác nhận đổi' : 'Gửi mã OTP'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. VỊ TRÍ NƠI LÀM VIỆC (BOTTOM SHEET)
  // ---------------------------------------------------------------------------
  Future<void> _viewOfficeLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _showLocationBottomSheet(position: pos);
    } catch (_) {
      final double officeLat = (c.data.office.latitude as num?)?.toDouble() ?? 10.7769;
      final double officeLng = (c.data.office.longitude as num?)?.toDouble() ?? 106.7009;
      final pos = Position(
        latitude: officeLat,
        longitude: officeLng,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      if (mounted) _showLocationBottomSheet(position: pos);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showLocationBottomSheet({required Position position}) async {
    final office = c.data.office;
    final double officeLat = (office.latitude as num?)?.toDouble() ?? 10.7769;
    final double officeLng = (office.longitude as num?)?.toDouble() ?? 106.7009;
    final double officeRadius = (office.radius as num?)?.toDouble() ?? 150.0;

    final distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      officeLat,
      officeLng,
    );
    final inRadius = distanceMeters <= officeRadius;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            Container(width: 44, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppColors.teal, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    office.name.isNotEmpty ? office.name : 'Vị trí nơi làm việc',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(inRadius ? 'Trong bán kính' : 'Ngoài bán kính'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(officeLat, officeLng),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app_cham_cong',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(officeLat, officeLng),
                          radius: officeRadius,
                          useRadiusInMeter: true,
                          color: AppColors.teal.withValues(alpha: 0.18),
                          borderColor: AppColors.teal,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(officeLat, officeLng),
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.business_rounded, color: AppColors.navy, size: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.straighten_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('Bán kính cho phép: ${officeRadius.toInt()} m • Cách trụ sở: ${distanceMeters.toStringAsFixed(1)} m', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. XÁC NHẬN ĐĂNG XUẤT
  // ---------------------------------------------------------------------------
  Future<void> _handleLogout() async {
    final user = c.user;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Xác nhận đăng xuất'),
          ],
        ),
        content: Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản "${user?.name ?? 'này'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.onLogout();
    }
  }

  // ===========================================================================
  // BUILD METHOD CHÍNH
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final user = c.user;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(child: Text('Chưa có thông tin tài khoản')),
      );
    }

    final isAdmin = c.isAdmin;
    final isManager = c.isManager || user.role == 'manager';
    final isEmployee = !isAdmin && !isManager;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. HEADER NAVY TRÀN VIỀN
              _buildTopNavyHeader(isAdmin: isAdmin),

              // 2. NỘI DUNG TÀI KHOẢN KÉO LÊN ĐÈ NHẸ LÊN HEADER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Transform.translate(
                  offset: const Offset(0, -22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // THẺ PROFILE CARD
                      _buildProfileCard(user, isAdmin: isAdmin, isManager: isManager, isEmployee: isEmployee),

                      const SizedBox(height: 18),

                      // KHỐI TRUNG GIAN ĐẶC THÙ CHO ADMIN HOẶC QUẢN LÝ
                      if (isAdmin) ...[
                        _buildAdminSystemSection(),
                        const SizedBox(height: 18),
                      ] else if (isManager) ...[
                        _buildManagerTeamSection(),
                        const SizedBox(height: 18),
                      ],

                      // KHỐI BẢO MẬT (DÙNG CHUNG THEO MOCKUP)
                      _buildSecuritySection(isEmployee: isEmployee),

                      const SizedBox(height: 24),

                      // NÚT ĐĂNG XUẤT ĐỎ NHẠT
                      _buildLogoutButton(),

                      const SizedBox(height: 14),

                      // FOOTER
                      const Center(
                        child: Text(
                          'Nhóm 09 • Phiên bản 1.0.0',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET CON: TOP NAVY HEADER
  // ===========================================================================
  Widget _buildTopNavyHeader({required bool isAdmin}) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1F3A),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 36),
      child: Row(
        children: [
          if (!widget.isTab && Navigator.of(context).canPop())
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tài khoản',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isAdmin ? 'Hồ sơ, hệ thống và bảo mật' : 'Hồ sơ và bảo mật',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET CON: THẺ PROFILE CARD
  // ===========================================================================
  Widget _buildProfileCard(
    Employee user, {
    required bool isAdmin,
    required bool isManager,
    required bool isEmployee,
  }) {
    final initialLetter = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row Avatar + Tên + Chip + Icon bút chì
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar tròn kèm camera badge
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF006766),
                      backgroundImage: _avatarBase64 != null
                          ? MemoryImage(base64Decode(_avatarBase64!))
                          : null,
                      child: _avatarBase64 == null
                          ? Text(
                              initialLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006766),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Họ tên & Chip vai trò
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildRoleChip(isAdmin: isAdmin, isManager: isManager),
                  ],
                ),
              ),

              // Nút icon bút chì góc trên bên phải cho Admin & Quản lý
              if (!isEmployee)
                IconButton(
                  onPressed: _openEditProfileDialog,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Các dòng thông tin
          _buildInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Tên đăng nhập',
            value: user.username,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.email_outlined,
            label: 'Email nhận OTP',
            value: user.email,
          ),

          // Phòng ban (Nhân viên và Quản lý)
          if (!isAdmin) ...[
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.corporate_fare_outlined,
              label: 'Phòng ban',
              value: () {
                final d = user.department.trim();
                if (d.isEmpty) return 'Chưa phân phòng ban';
                return d.toLowerCase().startsWith('phòng') ? d : 'Phòng $d';
              }(),
              highlightValue: true,
            ),
          ],

          // Nút "Chỉnh sửa hồ sơ" viền dành riêng cho Nhân viên
          if (isEmployee) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openEditProfileDialog,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Chỉnh sửa hồ sơ',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006766),
                  side: const BorderSide(color: Color(0xFF006766), width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleChip({required bool isAdmin, required bool isManager}) {
    if (isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, size: 11, color: Colors.amber),
            SizedBox(width: 4),
            Text(
              'Quản trị viên',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      );
    } else if (isManager) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F4F1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF99D5CF)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 12, color: Color(0xFF006766)),
            SizedBox(width: 4),
            Text(
              'Quản lý',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF006766)),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Text(
          'Nhân viên',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
        ),
      );
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool highlightValue = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: highlightValue ? const Color(0xFF006766) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WIDGET CON: KHỐI QUẢN TRỊ HỆ THỐNG (ADMIN)
  // ===========================================================================
  Widget _buildAdminSystemSection() {
    final officeRadius = c.data.office.radius.toInt();
    final shiftsCount = c.data.shifts.length;
    final deptsCount = c.data.departments.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quản trị hệ thống',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSystemCard(
                icon: Icons.location_on_rounded,
                iconBg: const Color(0xFFE0F2FE),
                iconColor: const Color(0xFF0284C7),
                title: 'Nơi làm việc',
                subtitle: 'Trụ sở • $officeRadius m',
                onTap: _viewOfficeLocation,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSystemCard(
                icon: Icons.schedule_rounded,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'Ca làm',
                subtitle: '$shiftsCount ca',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hệ thống hiện có $shiftsCount ca làm việc đang hoạt động.')),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSystemCard(
                icon: Icons.business_rounded,
                iconBg: const Color(0xFFF3E8FF),
                iconColor: const Color(0xFF9333EA),
                title: 'Phòng ban',
                subtitle: '$deptsCount phòng',
                onTap: () => DepartmentManagementSheet.show(context, c),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSystemCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET CON: KHỐI NHÓM CỦA TÔI (QUẢN LÝ)
  // ===========================================================================
  Widget _buildManagerTeamSection() {
    final deptName = c.user?.department.isNotEmpty == true ? c.user!.department : 'Kinh doanh';
    final deptEmployees = c.data.employees
        .where((e) => e.active && e.department.toLowerCase() == deptName.toLowerCase())
        .toList();
    final deptEmpIds = deptEmployees.map((e) => e.id).toSet();
    final pendingCount = c.data.requests
        .where((r) => r.status == 'pending' && deptEmpIds.contains(r.employeeId))
        .length;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final checkedInTodayCount = c.data.attendance
        .where((a) => deptEmpIds.contains(a.employeeId) && a.checkIn.toLocal().toString().startsWith(todayStr))
        .map((a) => a.employeeId)
        .toSet()
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Nhóm của tôi',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            if (widget.onNavigateToTimesheet != null)
              GestureDetector(
                onTap: widget.onNavigateToTimesheet,
                child: const Text(
                  'Xem bảng công',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF006766),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTeamMetricCard(
                value: '${deptEmployees.length}',
                label: 'Thành viên',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTeamMetricCard(
                value: '$pendingCount',
                label: 'Đơn chờ duyệt',
                isHighlighted: pendingCount > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTeamMetricCard(
                value: '$checkedInTodayCount/${deptEmployees.length}',
                label: 'Đã chấm công',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTeamMetricCard({
    required String value,
    required String label,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isHighlighted ? const Color(0xFFEA580C) : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET CON: KHỐI BẢO MẬT (CHUNG CHO CẢ 3 VAI TRÒ)
  // ===========================================================================
  Widget _buildSecuritySection({required bool isEmployee}) {
    final isEnrolled = _faceEnrolled == true;
    final isAdmin = c.isAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bảo mật',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 1. Khuôn mặt
              _buildSecurityTile(
                icon: Icons.face_retouching_natural_rounded,
                iconBg: const Color(0xFFE6F4F1),
                iconColor: const Color(0xFF006766),
                title: 'Khuôn mặt',
                subtitle: isEnrolled ? 'Đã đăng ký mẫu' : 'Chưa đăng ký mẫu',
                trailing: TextButton(
                  onPressed: _faceBusy ? null : () => _changeFaceEnrollment(remove: false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isEnrolled ? 'Đăng ký lại' : 'Đăng ký',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF006766),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

              // 2. Đăng nhập bằng camera + OTP (dành cho Nhân viên)
              if (isEmployee) ...[
                _buildSecurityTile(
                  icon: Icons.camera_alt_outlined,
                  iconBg: const Color(0xFFE6F4F1),
                  iconColor: const Color(0xFF006766),
                  title: 'Đăng nhập bằng camera + OTP',
                  subtitle: 'Dùng khuôn mặt thay mật khẩu',
                  trailing: Switch(
                    value: _allowFaceLogin && isEnrolled,
                    onChanged: isEnrolled
                        ? (v) => _setFaceLoginPreference(v)
                        : null,
                    activeThumbColor: const Color(0xFF006766),
                  ),
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),
              ],

              // 3. Vân tay của điện thoại
              _buildSecurityTile(
                icon: Icons.fingerprint_rounded,
                iconBg: const Color(0xFFE6F4F1),
                iconColor: const Color(0xFF006766),
                title: 'Vân tay của điện thoại',
                subtitle: _bioEnrolled
                    ? (isAdmin ? 'Mở app nhanh, không cần nhập mật khẩu' : 'Đã kích hoạt')
                    : 'Chưa kích hoạt',
                trailing: Switch(
                  value: _bioEnrolled,
                  onChanged: (_bioSupported && !_bioLoading)
                      ? (_) => _toggleBiometric()
                      : null,
                  activeThumbColor: const Color(0xFF006766),
                ),
              ),

              const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

              // 4. Đổi mật khẩu
              InkWell(
                onTap: _openChangePasswordDialog,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: _buildSecurityTile(
                  icon: Icons.lock_outline_rounded,
                  iconBg: const Color(0xFFE6F4F1),
                  iconColor: const Color(0xFF006766),
                  title: 'Đổi mật khẩu',
                  subtitle: 'Cần xác nhận bằng OTP',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET CON: NÚT ĐĂNG XUẤT
  // ===========================================================================
  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: InkWell(
        onTap: _handleLogout,
        borderRadius: BorderRadius.circular(16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFE11D48), size: 18),
            SizedBox(width: 8),
            Text(
              'Đăng xuất',
              style: TextStyle(
                color: Color(0xFFE11D48),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
