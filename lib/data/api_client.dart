import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static const String defaultBaseUrl =
      'https://webapi-chamcong-nhom9-tongnhatbaoan.onrender.com';

  final String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  String? _accessToken;
  String? _refreshToken;
  void Function()? onUnauthorized;

  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  }) : baseUrl =
           (baseUrl ??
                   const String.fromEnvironment(
                     'API_BASE_URL',
                     defaultValue: defaultBaseUrl,
                   ))
               .replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      _accessToken = await _secureStorage.read(key: 'jwt_access_token');
      _refreshToken = await _secureStorage.read(key: 'jwt_refresh_token');
    } catch (_) {
      // Fallback for platforms with secure storage issues
      _accessToken = _prefs?.getString('jwt_access_token');
      _refreshToken = _prefs?.getString('jwt_refresh_token');
    }
  }

  bool get hasTokens => _accessToken != null && _refreshToken != null;
  String? get refreshToken => _refreshToken;

  Future<void> setTokens({
    required String access,
    required String refresh,
  }) async {
    _accessToken = access;
    _refreshToken = refresh;
    try {
      await _secureStorage.write(key: 'jwt_access_token', value: access);
      await _secureStorage.write(key: 'jwt_refresh_token', value: refresh);
    } catch (_) {}
    await _prefs?.setString('jwt_access_token', access);
    await _prefs?.setString('jwt_refresh_token', refresh);
    try {
      if (await biometricEnabled) {
        await _secureStorage.write(key: 'bio_refresh_token', value: refresh);
      }
    } catch (_) {}
  }

  /// Sinh trắc học đang bật: refresh token được đồng bộ sang khóa bio_refresh_token
  /// để đăng nhập nhanh không cần mật khẩu/OTP.
  Future<bool> get biometricEnabled async {
    try {
      return await _secureStorage.read(key: 'bio_enabled') == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    try {
      await _secureStorage.delete(key: 'jwt_access_token');
      await _secureStorage.delete(key: 'jwt_refresh_token');
    } catch (_) {}
    await _prefs?.remove('jwt_access_token');
    await _prefs?.remove('jwt_refresh_token');
  }

  Map<String, String> _headers([bool withAuth = true]) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (withAuth && _accessToken != null) {
      h['Authorization'] = 'Bearer $_accessToken';
    }
    return h;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    if (query == null || query.isEmpty) return Uri.parse(fullUrl);
    final strQuery = query.map((k, v) => MapEntry(k, v?.toString() ?? ''))
      ..removeWhere((_, v) => v.isEmpty);
    return Uri.parse(fullUrl).replace(queryParameters: strQuery);
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    return _sendWithRetry(
      () => _http.get(_uri(path, query), headers: _headers(auth)),
      allowRefresh: auth,
    );
  }

  Future<dynamic> post(String path, {dynamic body, bool auth = true}) async {
    return _sendWithRetry(
      () => _http.post(
        _uri(path),
        headers: _headers(auth),
        body: body != null ? jsonEncode(body) : null,
      ),
      allowRefresh: auth,
    );
  }

  Future<dynamic> patch(String path, {dynamic body, bool auth = true}) async {
    return _sendWithRetry(
      () => _http.patch(
        _uri(path),
        headers: _headers(auth),
        body: body != null ? jsonEncode(body) : null,
      ),
      allowRefresh: auth,
    );
  }

  Future<dynamic> put(String path, {dynamic body, bool auth = true}) async {
    return _sendWithRetry(
      () => _http.put(
        _uri(path),
        headers: _headers(auth),
        body: body != null ? jsonEncode(body) : null,
      ),
      allowRefresh: auth,
    );
  }

  Future<dynamic> delete(String path, {dynamic body, bool auth = true}) async {
    return _sendWithRetry(
      () => _http.delete(
        _uri(path),
        headers: _headers(auth),
        body: body != null ? jsonEncode(body) : null,
      ),
      allowRefresh: auth,
    );
  }

  Future<dynamic> _sendWithRetry(
    Future<http.Response> Function() req, {
    bool allowRefresh = true,
  }) async {
    http.Response res;
    try {
      res = await req().timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw ApiException(
        408,
        'Quá thời gian kết nối tới máy chủ. Vui lòng thử lại.',
      );
    } catch (_) {
      throw ApiException(
        0,
        'Không kết nối được tới máy chủ ($baseUrl). Kiểm tra mạng.',
      );
    }

    if (allowRefresh && res.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        try {
          res = await req().timeout(const Duration(seconds: 90));
        } catch (_) {}
      } else {
        await clearTokens();
        onUnauthorized?.call();
        throw ApiException(
          401,
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        );
      }
    }

    return _parseResponse(res);
  }

  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final res = await _http
          .post(
            _uri('/api/auth/refresh'),
            headers: _headers(false),
            body: jsonEncode({'refreshToken': _refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        await setTokens(
          access: data['accessToken'],
          refresh: data['refreshToken'],
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  dynamic _parseResponse(http.Response res) {
    dynamic body;
    if (res.body.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        body = res.body;
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    String message = 'Lỗi hệ thống (${res.statusCode}).';
    if (body is Map && body['error'] != null) {
      message = body['error'].toString();
    } else if (body is Map && body['message'] != null) {
      message = body['message'].toString();
    } else if (res.statusCode == 403) {
      message = 'Bạn không có quyền thực hiện thao tác này.';
    } else if (res.statusCode == 404) {
      message = 'Dữ liệu không tìm thấy.';
    }

    throw ApiException(res.statusCode, message);
  }
}
