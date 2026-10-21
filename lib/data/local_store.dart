import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

/// Local prototype persistence only. A shared API must authorize each operation,
/// not expose this entire snapshot to employee clients.
abstract interface class DataStore {
  Future<AppData> load();
  Future<void> save(AppData data);
}

class LocalStore implements DataStore {
  static const key = 'tong_nhat_bao_an_attendance_v1';
  @override
  Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null ? AppData() : AppData.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(data.toJson()))) {
      throw StateError('Không lưu được dữ liệu trên thiết bị.');
    }
  }
}
