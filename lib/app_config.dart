/// Cấu hình toàn cục cho ứng dụng Chấm Công Thông Minh.
class AppConfig {
  /// Cờ bật/tắt yêu cầu quét mã QR khi chấm công
  /// - `false`: Luồng tối ưu 2 chạm (GPS tự kiểm tra -> Xác thực khuôn mặt -> Ghi nhận).
  ///            Bỏ nút quét QR của nhân viên và ẩn nút "Hiển thị QR động" phía admin.
  /// - `true`: Yêu cầu bắt buộc phải quét thêm mã QR văn phòng.
  static const bool requireQr = false;
}
