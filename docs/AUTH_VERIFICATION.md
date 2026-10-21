# Kiểm tra đăng ký và đăng nhập qua Web API

## Bản sửa

- Đóng form đăng ký trước khi mở hộp thoại OTP, tránh đóng nhầm hộp thoại mới.
- Thêm Gửi lại OTP trong hộp thoại xác minh email.
- Đăng ký lại bằng đúng tên đăng nhập, email và mật khẩu cũ sẽ tiếp tục xác minh tài khoản chưa xác minh; không thay mật khẩu hoặc vai trò của tài khoản đó.
- Mọi repository mặc định dùng chung một ApiClient để chia sẻ phiên đăng nhập.
- Sai mật khẩu/OTP ở endpoint công khai không kích hoạt refresh token hoặc tự gửi lại OTP sai.
- Đăng xuất gửi refresh token để server thu hồi, kể cả khi access token hết hạn. Endpoint chỉ thu hồi token khớp hash bí mật được gửi lên, không cấp quyền truy cập dữ liệu.
- Thời gian chờ API tăng lên 90 giây để giảm lỗi khi Render Free đang khởi động; không tự retry đăng ký/đăng nhập khi timeout.
- Khi xác thực OTP đăng nhập, backend kiểm tra lại tài khoản còn hoạt động và đã xác minh email.

## Tự kiểm tra trên điện thoại sau khi deploy

1. Dùng email Gmail mình kiểm soát, đăng ký tên đăng nhập mới và mật khẩu ít nhất 8 ký tự. Hộp thoại OTP phải còn mở sau khi form đăng ký đóng.
2. Nhập OTP sai: báo lỗi, không vào Dashboard. Nhập mã đúng: trở về đăng nhập.
3. Đăng nhập sai mật khẩu: bị từ chối. Đăng nhập đúng: nhận một OTP đăng nhập mới, chưa vào Dashboard cho đến khi xác thực.
4. Nhập OTP đúng: vào Dashboard của nhân viên. Thử mã đăng ký ở bước đăng nhập: phải bị từ chối.
5. Đăng xuất, đăng nhập lại. Tài khoản admin có sẵn phải vào trang quản trị; tài khoản tự đăng ký chỉ có vai trò nhân viên.
6. Với tài khoản mới khác: đăng ký rồi Hủy xác minh. Đăng ký lại cùng email/tên đăng nhập/mật khẩu để lấy OTP mới. Thử Gửi lại OTP khi mã hết hạn.
7. Sai OTP 5 lần: challenge bị khóa; quay lại xin mã mới. Mã đã dùng không được dùng lần hai.
8. Nếu nhận 503 gửi email: kiểm tra cấu hình Brevo và Live tail. Không bật trả mã trực tiếp ở Production.

Các lần test tạo tài khoản thật trong database. Chỉ dùng tài khoản thử nghiệm do mình kiểm soát.

## Kiểm tra tự động

```powershell
dotnet build WebAPI_TongNhatBaoAn --no-restore
dotnet run --project tool/OtpEmailChecks --no-restore
flutter test --no-pub test/auth_api_test.dart
```

Bộ test auth mới giả lập HTTP và kiểm tra chuyển form đăng ký sang hộp thoại OTP, gửi lại và xác minh. Các test local-mode cũ trong domain_test.dart và widget_test.dart chưa được chuyển sang kiến trúc API, không dùng chúng làm bằng chứng luồng API hoạt động.

Tại lần sửa này: backend build đạt; 6 kiểm tra bộ gửi email đạt; phân tích tĩnh các file Dart sửa và test auth không có vấn đề. Chưa chạy được Flutter widget tests vì công cụ không có quyền mở SDK cache lockfile. Chưa kiểm tra tích hợp PostgreSQL/email thật: Docker local không chạy và chưa có phiên kiểm thử Gmail trên Render.
