# Checklist kiểm thử và bàn giao

## Phạm vi kiểm tra trong phiên triển khai

- Khởi tạo skeleton Android/web bằng Flutter SDK 3.44.2 trên máy.
- Parse/format toàn bộ Dart; kiểm tra tĩnh với các thư viện có sẵn. Các plugin chưa tải được nên chưa có kết quả `flutter analyze` sạch cho toàn bộ app.
- `flutter pub get` bị chặn ở kết nối tới pub.dev (socket/DNS). Chưa tạo lockfile hoàn chỉnh.
- Flutter test runner bị môi trường chặn kết nối loopback 127.0.0.1 trước khi chạy test. Không coi các test Flutter là đã vượt qua.
- `dart tool/check_models.dart`: **6/6 kiểm tra đạt**, gồm ca qua năm, ca ngày, số giờ, giải thích bất thường, JSON và schema version. Đây chỉ là kiểm tra mô hình dữ liệu, không thay thế test đăng nhập, controller hoặc phần cứng.
- Chưa build APK thành công, chưa test camera/GPS thật. Không có bằng chứng xác nhận UI trên thiết bị đã hoàn chỉnh. Đã bỏ đo chuyển động; đăng nhập khuôn mặt được chọn thay thế nhưng chưa triển khai.

## Lệnh trên máy có mạng

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
dart tool/check_models.dart
flutter test
flutter run
flutter build apk --debug
```

## Kịch bản thủ công

| Nhóm | Thao tác | Kết quả mong đợi |
|---|---|---|
| Khởi tạo | Lần đầu mở app, tạo Admin | Không có dữ liệu mẫu; chỉ được tạo Admin bootstrap một lần |
| Đăng ký | Email sai, email trùng khác hoa/thường, username ngắn, password <8 | Không lưu; hiển thị lỗi |
| Login | Sai mật khẩu, OTP sai 5 lần, OTP quá 2 phút, dùng lại OTP | Không đăng nhập; yêu cầu bắt đầu lại |
| Phân quyền | Employee xem các tab; gọi lệnh quản trị trong test | Không có UI quản trị; lệnh bị từ chối |
| CRUD nhân viên | Thêm, tìm, sửa, phân ca, khóa, xóa nhân viên chưa có lịch sử | Dữ liệu lưu và còn sau khi mở lại |
| Toàn vẹn | Xóa ca đang phân; xóa nhân viên có công; tự khóa Admin | Bị từ chối, hướng dẫn cách xử lý |
| GPS | Từ chối quyền, tắt Location, denied forever, timeout | Hiện hướng dẫn/lỗi, không crash hoặc chấm công thành công giả |
| Geofence | Ra ngoài bán kính, sai số >80m, GPS cũ >60s | Từ chối chấm công, lấy lại vị trí |
| QR | Camera không cấp quyền, mã sai, mã quá hạn | Không chấm công; cho phép thử lại |
| Chấm công | Vào, ra, chấm lại; bấm nhanh nhiều lần | Một bản ghi ca; không có ca trùng |
| Ca đêm | Ca 22:00–06:00, chấm sau nửa đêm | Thuộc ca của ngày trước |
| Đơn | Tạo/sửa/xóa đơn pending, trùng ngày nghỉ | CRUD đúng; chặn trùng khoảng nghỉ |
| Duyệt | Admin duyệt/từ chối kèm nhận xét; tự duyệt; sửa đơn đã duyệt | Đúng quyền; đơn đã duyệt không bị sửa/xóa |
| Nghỉ phép | Chấm vào ngày nghỉ đã duyệt | Bị chặn, hướng dẫn liên hệ Admin |
| Khuôn mặt (chưa triển khai) | Đăng ký mẫu sau xác thực tài khoản; thử đúng/sai người, ảnh chụp lại, nhiều mặt, thiếu sáng | Chỉ tài khoản đối sánh hợp lệ được đăng nhập; không nhận nhầm việc phát hiện mặt là xác thực |
| Chia sẻ | Bấm chia sẻ vị trí rồi hủy/gửi theo ý người dùng | Mở bảng chia sẻ hệ thống, không tự gửi |
| Báo cáo | Lọc ngày, tìm tên, copy CSV có dấu phẩy/dấu nháy | Kết quả đúng; CSV escape đúng |
| UI | Màn nhỏ, bàn phím, font lớn, xoay màn hình | Không che nút/overflow nghiêm trọng |
| Multi-device | Sau khi triển khai API, 4 máy dùng chung dữ liệu | Thay đổi một máy hiển thị ở máy khác |

Chỉ đánh dấu đã đạt sau khi thực hiện thực tế và ghi thiết bị/phiên bản/người kiểm thử. Ba chức năng lựa chọn cần đúng nội dung nhóm đã thuyết trình, phải xác nhận với thầy nếu nhóm đã chọn nội dung khác.
