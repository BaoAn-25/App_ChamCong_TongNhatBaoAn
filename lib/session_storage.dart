import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Quản lý lưu trữ phiên đăng nhập và định danh thiết bị an toàn
/// Sử dụng FlutterSecureStorage, tuyệt đối KHÔNG lưu mật khẩu.
class SessionStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyAccessToken = 'jwt_access_token';
  static const _keyRefreshToken = 'jwt_refresh_token';
  static const _keyExpiresAt = 'jwt_expires_at';
  static const _keyRememberMe = 'session_remember_me';
  static const _keyDeviceId = 'app_device_id';
  static const _prefixTrustedDevice = 'trusted_device_';

  /// 5. Lấy hoặc tạo mới DeviceId (UUID tạo một lần duy nhất trên máy)
  static Future<String> getDeviceId() async {
    try {
      var deviceId = await _storage.read(key: _keyDeviceId);
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = const Uuid().v4();
        await _storage.write(key: _keyDeviceId, value: deviceId);
      }
      return deviceId;
    } catch (_) {
      return 'fallback-device-id';
    }
  }

  /// 1 & 6. Lưu thông tin phiên đăng nhập
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
    bool rememberMe = true,
  }) async {
    try {
      await _storage.write(key: _keyRememberMe, value: rememberMe.toString());
      if (rememberMe) {
        await _storage.write(key: _keyAccessToken, value: accessToken);
        await _storage.write(key: _keyRefreshToken, value: refreshToken);
        await _storage.write(
          key: _keyExpiresAt,
          value: expiresAt.toUtc().toIso8601String(),
        );
      } else {
        // Tắt ghi nhớ đăng nhập: xóa token lưu trữ bền vững
        await clearTokens();
      }
    } catch (_) {}
  }

  /// Lấy Access Token đã lưu
  static Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: _keyAccessToken);
    } catch (_) {
      return null;
    }
  }

  /// Lấy Refresh Token đã lưu
  static Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (_) {
      return null;
    }
  }

  /// Lấy thời điểm hết hạn của phiên
  static Future<DateTime?> getExpiresAt() async {
    try {
      final str = await _storage.read(key: _keyExpiresAt);
      if (str == null) return null;
      return DateTime.tryParse(str);
    } catch (_) {
      return null;
    }
  }

  /// Trạng thái công tắc Ghi nhớ đăng nhập
  static Future<bool> isRememberMeEnabled() async {
    try {
      final val = await _storage.read(key: _keyRememberMe);
      // Mặc định là bật (true) nếu chưa từng thiết lập
      return val == null || val == 'true';
    } catch (_) {
      return true;
    }
  }

  /// 2. Kiểm tra token có tồn tại và còn hạn sử dụng hay không
  static Future<bool> isSessionValid() async {
    final remember = await isRememberMeEnabled();
    if (!remember) return false;

    final token = await getAccessToken();
    if (token == null || token.isEmpty) return false;

    final expiresAt = await getExpiresAt();
    if (expiresAt == null) return false;

    // Token còn hạn ít nhất 10 giây tính đến hiện tại
    return DateTime.now().toUtc().isBefore(
      expiresAt.subtract(const Duration(seconds: 10)),
    );
  }

  /// 7. Xóa sạch token phiên đăng nhập (khi đăng xuất hoặc hết hạn)
  static Future<void> clearSession() async {
    try {
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyExpiresAt);
    } catch (_) {}
  }

  static Future<void> clearTokens() => clearSession();

  /// 5. Đánh dấu thiết bị hiện tại là thiết bị tin cậy của tài khoản
  static Future<void> markDeviceTrusted(String username, String deviceId) async {
    try {
      final key = '$_prefixTrustedDevice${username.toLowerCase()}_$deviceId';
      await _storage.write(key: key, value: 'true');
    } catch (_) {}
  }

  /// 4. Kiểm tra thiết bị này có phải là thiết bị tin cậy của tài khoản
  static Future<bool> isDeviceTrusted(String username, String deviceId) async {
    try {
      final key = '$_prefixTrustedDevice${username.toLowerCase()}_$deviceId';
      final val = await _storage.read(key: key);
      return val == 'true';
    } catch (_) {
      return false;
    }
  }
}
