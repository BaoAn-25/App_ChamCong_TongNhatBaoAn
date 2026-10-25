import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_config.dart';
import '../../core/app_theme.dart';
import '../../data/face_service.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/biometric_page.dart';
import '../../ui/face_camera_page.dart';
import '../../widgets/app_widgets.dart';

/// Màn hình Tài khoản dành cho Quản trị viên (Admin Account Screen):
/// 7. Header hồ sơ: Avatar (đổi ảnh), họ tên, huy hiệu vai trò Admin, thông tin chi tiết (@username, email, phòng ban), nút "Chỉnh sửa hồ sơ".
/// 8. Thẻ Khuôn mặt: StatusChip "Đã đăng ký" / "Chưa đăng ký", nút "Đăng ký lại", công tắc "Cho phép đăng nhập bằng camera + OTP".
///    Câu về QR chỉ hiện khi requireQr = true; đã bỏ cảnh báo kỹ thuật về chống ảnh giả.
/// 9. Thẻ Sinh trắc học: Công tắc và trạng thái (Thiết bị chưa hỗ trợ / Chưa kích hoạt / Đã bật).
/// 10. Vị trí hiện tại: Bottom sheet gồm bản đồ nhỏ (flutter_map + OpenStreetMap) có marker vị trí và vòng tròn bán kính nơi làm việc,
///     địa chỉ, tọa độ, sai số, khoảng cách tới nơi làm việc kèm chip "Trong bán kính" / "Ngoài bán kính", nút "Mở Google Maps" và "Sao chép tọa độ".
/// 11. Mục "Về ứng dụng" gập mặc định (ExpansionTile): thông tin nhóm, công nghệ sử dụng (bỏ chữ "AI Insights").
/// 12. Nút "Đăng xuất" nền đỏ nhạt (#FDECEC), chữ đỏ (#D64545) nằm cuối trang.
class AdminAccountScreen extends StatefulWidget {
  final AppController controller;
  final VoidCallback onLogout;

  const AdminAccountScreen({
    super.key,
    required this.controller,
    required this.onLogout,
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
  String? _faceError;

  // Biometric status
  bool _bioSupported = false;
  bool _bioEnrolled = false;
  List<dynamic> _bioTypes = [];
  bool _bioLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    _loadFaceStatus();
    _loadBiometricStatus();
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

  /// Mở hộp thoại chỉnh sửa hồ sơ (Họ tên & Email)
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
                    child: PrimaryButton(
                      title: 'Lưu thay đổi',
                      isLoading: isSaving,
                      onPressed: () async {
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
          _allowFaceLogin = status.enrolled ? status.allowLogin : true;
          _faceError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _faceError = e.toString());
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
      _faceError = null;
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
      if (mounted) setState(() => _faceError = e.toString());
    } finally {
      if (mounted) setState(() => _faceBusy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. SINH TRẮC HỌC
  // ---------------------------------------------------------------------------
  Future<void> _loadBiometricStatus() async {
    final supported = await BiometricLoginHelper.isDeviceSupported;
    final enrolled = await BiometricLoginHelper.isEnabled;
    final types = await BiometricLoginHelper.availableBiometrics;
    if (mounted) {
      setState(() {
        _bioSupported = supported;
        _bioEnrolled = enrolled;
        _bioTypes = types;
        _bioLoading = false;
      });
    }
  }

  Future<void> _toggleBiometric() async {
    if (_bioEnrolled) {
      final confirmTurnOff = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tắt đăng nhập sinh trắc'),
          content: const Text('Bạn có chắc chắn muốn tắt đăng nhập bằng sinh trắc học? Lần sau bạn sẽ cần nhập mật khẩu và OTP.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tắt sinh trắc'),
            ),
          ],
        ),
      );
      if (confirmTurnOff == true) {
        await BiometricLoginHelper.unenroll();
        if (mounted) {
          setState(() => _bioEnrolled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tắt đăng nhập bằng sinh trắc học.')),
          );
        }
      }
    } else {
      final refresh = c.client.refreshToken;
      if (refresh == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại để bật sinh trắc.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      final authed = await BiometricLoginHelper.authenticate();
      if (!authed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Xác thực sinh trắc học thất bại hoặc đã bị huỷ.')),
          );
        }
        return;
      }
      await BiometricLoginHelper.enroll(refresh);
      if (mounted) {
        setState(() => _bioEnrolled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã kích hoạt đăng nhập sinh trắc học thành công!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 10. VỊ TRÍ HIỆN TẠI (BOTTOM SHEET BẢN ĐỒ)
  // ---------------------------------------------------------------------------
  Future<void> _determineAndShowCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      // 1. Kiểm tra quyền và lấy GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Dịch vụ định vị (GPS) trên thiết bị chưa được bật.';
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Quyền truy cập vị trí bị từ chối.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Quyền truy cập vị trí bị từ chối vĩnh viễn. Vui lòng cấp quyền trong Cài đặt.';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      // 2. Tra cứu địa chỉ thực tế (Geocoding)
      String address = 'Không tra cứu được địa chỉ cụ thể.';
      try {
        final placemarks = await geo.Geocoding()
            .placemarkFromCoordinates(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 8));
        if (placemarks.isNotEmpty) {
          final pm = placemarks.first;
          final parts = [
            pm.street,
            pm.subLocality,
            pm.locality,
            pm.subAdministrativeArea,
            pm.administrativeArea,
            pm.country,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).toSet().toList();
          if (parts.isNotEmpty) {
            address = parts.join(', ');
          }
        }
      } catch (_) {}

      // 3. Tính khoảng cách tới nơi làm việc (nếu có)
      final office = c.data.office;
      double? distanceToOffice;
      bool isInRadius = false;
      if (office.configured && office.latitude != null && office.longitude != null) {
        distanceToOffice = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          office.latitude!,
          office.longitude!,
        );
        isInRadius = distanceToOffice <= office.radius;
      }

      if (!mounted) return;
      _showLocationBottomSheet(
        position: position,
        address: address,
        distanceToOffice: distanceToOffice,
        isInRadius: isInRadius,
        office: office,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi định vị: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showLocationBottomSheet({
    required Position position,
    required String address,
    required double? distanceToOffice,
    required bool isInRadius,
    required Office office,
  }) {
    final userPoint = LatLng(position.latitude, position.longitude);
    final officePoint = (office.configured && office.latitude != null && office.longitude != null)
        ? LatLng(office.latitude!, office.longitude!)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded, color: AppColors.teal),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Vị trí GPS hiện tại',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),

            // 1. Bản đồ OpenStreetMap thu nhỏ
            SizedBox(
              height: 220,
              width: double.infinity,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: userPoint,
                  initialZoom: 16.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app_cham_cong_tong_nhat_bao_an',
                  ),
                  if (officePoint != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: officePoint,
                          radius: office.radius,
                          useRadiusInMeter: true,
                          color: AppColors.teal.withValues(alpha: 0.15),
                          borderColor: AppColors.teal,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      // Marker nơi làm việc
                      if (officePoint != null)
                        Marker(
                          point: officePoint,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.business_rounded,
                            color: AppColors.navy,
                            size: 36,
                          ),
                        ),
                      // Marker vị trí người dùng
                      Marker(
                        point: userPoint,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.teal,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. Chi tiết thông tin vị trí
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chip trạng thái bán kính
                    if (distanceToOffice != null)
                      Row(
                        children: [
                          StatusChip(
                            isInRadius ? 'Trong bán kính' : 'Ngoài bán kính',
                            icon: isInRadius ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Cách nơi làm việc: ${distanceToOffice.round()} m (quy định: ${office.radius.round()} m)',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),

                    // Địa chỉ cụ thể
                    const Text(
                      'Địa chỉ cụ thể:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Tọa độ & sai số GPS
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.gps_fixed_rounded, size: 18, color: AppColors.teal),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tọa độ: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sai số GPS: ±${position.accuracy.round()} m',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Nút thao tác
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            title: 'Sao chép tọa độ',
                            icon: Icons.copy_rounded,
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: '${position.latitude}, ${position.longitude}'),
                              );
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Đã sao chép tọa độ vào bộ nhớ tạm')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            title: 'Mở Google Maps',
                            icon: Icons.open_in_new_rounded,
                            onPressed: () async {
                              final uri = Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}',
                              );
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Không thể mở Google Maps')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD METHOD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final user = c.user;
    if (user == null) {
      return const Center(child: Text('Chưa có thông tin tài khoản'));
    }

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space16),
      children: [
        // ====================================================================
        // 7. HEADER HỒ SƠ
        // ====================================================================
        _buildProfileHeaderCard(user),
        const SizedBox(height: 16),

        // ====================================================================
        // 8. THẺ KHUÔN MẶT
        // ====================================================================
        _buildFaceCard(),
        const SizedBox(height: 16),

        // ====================================================================
        // 9. THẺ SINH TRẮC HỌC
        // ====================================================================
        _buildBiometricCard(),
        const SizedBox(height: 16),

        // ====================================================================
        // 10. THẺ VỊ TRÍ HIỆN TẠI
        // ====================================================================
        _buildLocationCard(),
        const SizedBox(height: 16),

        // ====================================================================
        // 11. VỀ ỨNG DỤNG (GẬP MẶC ĐỊNH - ExpansionTile)
        // ====================================================================
        _buildAboutAppTile(),
        const SizedBox(height: 28),

        // ====================================================================
        // 12. NÚT ĐĂNG XUẤT CUỐI TRANG (#FDECEC, chữ #D64545)
        // ====================================================================
        _buildLogoutButton(),
        const SizedBox(height: 32),
      ],
    );
  }

  /// 7. Header Hồ sơ cá nhân
  Widget _buildProfileHeaderCard(Employee user) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.teal,
                      backgroundImage: _avatarBase64 != null
                          ? MemoryImage(base64Decode(_avatarBase64!))
                          : null,
                      child: _avatarBase64 == null
                          ? Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'A',
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
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.teal,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.deepPurple,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),

          _buildProfileInfoItem(
            icon: Icons.badge_outlined,
            label: 'Tên đăng nhập',
            value: '@${user.username}',
          ),
          const SizedBox(height: 8),
          _buildProfileInfoItem(
            icon: Icons.email_outlined,
            label: 'Email nhận mã OTP',
            value: user.email.isEmpty ? 'Chưa thiết lập' : user.email,
          ),
          const SizedBox(height: 8),
          _buildProfileInfoItem(
            icon: Icons.business_outlined,
            label: 'Phòng ban',
            value: user.department.isEmpty ? 'Ban Quản trị' : user.department,
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              title: 'Chỉnh sửa hồ sơ',
              icon: Icons.edit_outlined,
              onPressed: _openEditProfileDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// 8. Thẻ Khuôn mặt
  Widget _buildFaceCard() {
    final isEnrolled = _faceEnrolled == true;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.face_retouching_natural_rounded, color: AppColors.teal, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Xác thực khuôn mặt',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              StatusChip(
                isEnrolled ? 'Đã đăng ký' : 'Chưa đăng ký',
                icon: isEnrolled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Câu về QR chỉ hiện khi requireQr = true
          if (AppConfig.requireQr)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Mã QR và GPS là bắt buộc khi chấm công.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),

          if (_faceError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _faceError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cho phép đăng nhập bằng camera + OTP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Áp dụng mẫu khuôn mặt cho xác thực khi mở ứng dụng', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            value: _allowFaceLogin,
            onChanged: _faceBusy ? null : (val) => setState(() => _allowFaceLogin = val),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  title: isEnrolled ? 'Đăng ký lại mẫu' : 'Đăng ký khuôn mặt',
                  icon: Icons.add_a_photo_outlined,
                  isLoading: _faceBusy,
                  onPressed: () => _changeFaceEnrollment(remove: false),
                ),
              ),
              if (isEnrolled) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _faceBusy ? null : () => _changeFaceEnrollment(remove: true),
                  child: const Text('Xóa mẫu', style: TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _getBiometricLabel() {
    if (_bioTypes.any((t) => t.toString().contains('face'))) return 'Face ID';
    if (_bioTypes.any((t) => t.toString().contains('fingerprint'))) return 'Vân tay';
    return 'Sinh trắc học';
  }

  /// 9. Thẻ Sinh trắc học
  Widget _buildBiometricCard() {
    String bioStatusText;
    IconData bioStatusIcon;
    Color bioStatusColor;

    if (!_bioSupported) {
      bioStatusText = 'Thiết bị chưa hỗ trợ';
      bioStatusIcon = Icons.cancel_outlined;
      bioStatusColor = AppColors.textSecondary;
    } else if (_bioEnrolled) {
      bioStatusText = 'Đã bật';
      bioStatusIcon = Icons.check_circle_outline;
      bioStatusColor = AppColors.success;
    } else {
      bioStatusText = 'Chưa kích hoạt';
      bioStatusIcon = Icons.radio_button_unchecked;
      bioStatusColor = AppColors.warning;
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fingerprint_rounded, color: AppColors.teal, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Đăng nhập sinh trắc học',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              StatusChip(bioStatusText, icon: bioStatusIcon),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Mở khóa nhanh bằng vân tay hoặc Face ID trên thiết bị mà không cần nhập lại mã OTP.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 6),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật xác thực sinh trắc', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _bioSupported
                  ? (_bioEnrolled ? 'Đang kích hoạt ${_getBiometricLabel()}' : 'Gạt để kích hoạt ${_getBiometricLabel()}')
                  : 'Thiết bị không có cảm biến vân tay/Face ID hợp lệ',
              style: TextStyle(fontSize: 11, color: bioStatusColor),
            ),
            value: _bioEnrolled,
            onChanged: (_bioSupported && !_bioLoading) ? (_) => _toggleBiometric() : null,
          ),
        ],
      ),
    );
  }

  /// 10. Thẻ Vị trí hiện tại
  Widget _buildLocationCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.my_location_rounded, color: AppColors.teal, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Kiểm tra vị trí GPS',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Xác định tọa độ GPS và địa chỉ thực tế xem bạn có đang nằm trong bán kính nơi làm việc hay không.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              title: 'Xác định vị trí hiện tại',
              icon: Icons.near_me_outlined,
              isLoading: _isLocating,
              onPressed: _determineAndShowCurrentLocation,
            ),
          ),
        ],
      ),
    );
  }

  /// 11. Mục Về ứng dụng (Gập mặc định)
  Widget _buildAboutAppTile() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded, color: AppColors.navy, size: 20),
          ),
          title: const Text(
            'Về ứng dụng',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          subtitle: const Text(
            'Chấm Công Thông Minh • Nhóm 09',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: const [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: AppColors.border, height: 1),
                  SizedBox(height: 12),
                  Text(
                    'Thông tin đồ án & Công nghệ tích hợp:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Nhóm thực hiện: Nhóm 09 — Tống Nhật Bảo An\n'
                    '• Backend: ASP.NET Core 10 (Render Cloud + Neon PostgreSQL)\n'
                    '• Xác thực bảo mật: Mật khẩu + OTP Brevo HTTPS API + Biometric Secure Storage\n'
                    '• Chấm công: GPS Geofencing + Nhận diện khuôn mặt (Face Matching)\n'
                    '• Thống kê: Thống kê và cảnh báo tự động + Biểu đồ fl_chart',
                    style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 12. Nút Đăng xuất ở cuối trang (#FDECEC, chữ #D64545)
  Widget _buildLogoutButton() {
    return InkWell(
      onTap: widget.onLogout,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.errorBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
            SizedBox(width: 8),
            Text(
              'Đăng xuất tài khoản',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
