import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/app_controller.dart';
import 'common.dart';

/// Đăng nhập nhanh bằng sinh trắc học (khuôn mặt / vân tay).
/// Sinh trắc học thay thế bước OTP: sau khi xác thực thiết bị thành công,
/// phiên được khôi phục bằng refresh token lưu trong Secure Storage.
class BiometricLoginHelper {
  static const _storage = FlutterSecureStorage();
  static const _keyEnabled = 'bio_enabled';
  static const _keyRefresh = 'bio_refresh_token';
  static final _auth = LocalAuthentication();

  /// Kiểm tra thiết bị hỗ trợ sinh trắc học
  static Future<bool> get isDeviceSupported async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra có loại sinh trắc nào khả dụng
  static Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Xác thực sinh trắc
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Xác thực để đăng nhập nhanh vào App Chấm Công',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra người dùng đã đăng ký sinh trắc chưa
  static Future<bool> get isEnabled async {
    try {
      final val = await _storage.read(key: _keyEnabled);
      return val == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Đăng ký sinh trắc — lưu refresh token của phiên đã xác thực (mật khẩu + OTP).
  /// Không lưu mật khẩu. Token được ApiClient tự đồng bộ khi bị xoay vòng.
  static Future<void> enroll(String refreshToken) async {
    await _storage.write(key: _keyEnabled, value: 'true');
    await _storage.write(key: _keyRefresh, value: refreshToken);
  }

  /// Lấy refresh token đã lưu (chỉ gọi sau khi xác thực sinh trắc thành công)
  static Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefresh);
    } catch (_) {
      return null;
    }
  }

  /// Xóa đăng ký sinh trắc
  static Future<void> unenroll() async {
    await _storage.delete(key: _keyEnabled);
    await _storage.delete(key: _keyRefresh);
  }
}

/// Widget quản lý cài đặt sinh trắc trong trang Profile
class BiometricSettingsCard extends StatefulWidget {
  final AppController controller;
  const BiometricSettingsCard({super.key, required this.controller});

  @override
  State<BiometricSettingsCard> createState() => _BiometricSettingsCardState();
}

class _BiometricSettingsCardState extends State<BiometricSettingsCard> {
  bool _supported = false;
  bool _enrolled = false;
  List<BiometricType> _types = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final supported = await BiometricLoginHelper.isDeviceSupported;
    final enrolled = await BiometricLoginHelper.isEnabled;
    final types = await BiometricLoginHelper.availableBiometrics;
    if (mounted) {
      setState(() {
        _supported = supported;
        _enrolled = enrolled;
        _types = types;
        _loading = false;
      });
    }
  }

  String _biometricLabel() {
    if (_types.contains(BiometricType.face)) return 'Khuôn mặt (Face ID)';
    if (_types.contains(BiometricType.fingerprint)) return 'Vân tay (Fingerprint)';
    if (_types.contains(BiometricType.iris)) return 'Mống mắt (Iris)';
    if (_types.contains(BiometricType.strong)) return 'Sinh trắc học mạnh';
    if (_types.contains(BiometricType.weak)) return 'Sinh trắc học';
    return 'Sinh trắc học';
  }

  IconData _biometricIcon() {
    if (_types.contains(BiometricType.face)) return Icons.face_rounded;
    if (_types.contains(BiometricType.fingerprint)) return Icons.fingerprint_rounded;
    return Icons.security_rounded;
  }

  Future<void> _toggleBiometric() async {
    if (_enrolled) {
      final ok = await confirm(
        context,
        'Tắt đăng nhập bằng ${_biometricLabel()}?\nBạn sẽ cần nhập mật khẩu và mã OTP mỗi lần đăng nhập.',
      );
      if (ok) {
        await BiometricLoginHelper.unenroll();
        if (mounted) {
          setState(() => _enrolled = false);
          message(context, 'Đã tắt đăng nhập sinh trắc học.');
        }
      }
    } else {
      final refresh = widget.controller.client.refreshToken;
      if (refresh == null) {
        message(context, 'Phiên đăng nhập không hợp lệ. Hãy đăng nhập lại bằng mật khẩu + OTP.');
        return;
      }
      final authed = await BiometricLoginHelper.authenticate();
      if (!authed) {
        if (mounted) message(context, 'Xác thực sinh trắc học thất bại hoặc đã bị hủy.');
        return;
      }
      await BiometricLoginHelper.enroll(refresh);
      if (mounted) {
        setState(() => _enrolled = true);
        message(context, 'Đã kích hoạt đăng nhập bằng ${_biometricLabel()}. Lần sau chỉ cần quét là vào, không cần OTP.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    return Section(
      title: 'Đăng nhập sinh trắc học',
      subtitle: _supported
          ? 'Hỗ trợ: ${_biometricLabel()}'
          : 'Thiết bị không hỗ trợ sinh trắc học',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _enrolled
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _enrolled
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _enrolled
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : const Color(0xFF64748B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _biometricIcon(),
                    color: _enrolled
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _enrolled ? 'Đã kích hoạt' : 'Chưa kích hoạt',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _enrolled
                              ? const Color(0xFF065F46)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _enrolled
                            ? 'Đăng nhập nhanh bằng ${_biometricLabel()} mà không cần nhập mật khẩu.'
                            : 'Bật để đăng nhập nhanh lần sau mà không cần nhập mật khẩu.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_supported)
            SizedBox(
              width: double.infinity,
              child: _enrolled
                  ? OutlinedButton.icon(
                      onPressed: _toggleBiometric,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Tắt đăng nhập sinh trắc học'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _toggleBiometric,
                      icon: Icon(_biometricIcon(), size: 18),
                      label: Text('Kích hoạt ${_biometricLabel()}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF087F8C),
                        foregroundColor: Colors.white,
                      ),
                    ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Thiết bị này không hỗ trợ sinh trắc học. Hãy sử dụng đăng nhập bằng mật khẩu + OTP.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}