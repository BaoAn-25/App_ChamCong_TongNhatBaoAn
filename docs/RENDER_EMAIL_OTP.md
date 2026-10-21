# Gửi OTP thật trên Render qua Brevo HTTPS API

Backend dùng HTTPS cổng 443; không dùng Gmail SMTP cổng 587 nữa.

## Cấu hình một lần

1. Đăng ký/đăng nhập https://app.brevo.com. Hoàn tất xác minh tài khoản và kích hoạt gửi transactional email nếu được yêu cầu.
2. Trong phần Senders, thêm và xác minh email người gửi. Hoàn tất xác thực domain nếu Brevo yêu cầu. Email này phải là email bạn kiểm soát.
3. Trong SMTP & API → API Keys, tạo API key. Dùng **API key**, không dùng SMTP key hoặc mật khẩu ứng dụng Gmail.
4. Trong Render → dịch vụ Web API → Environment, thêm:

| Biến | Giá trị |
|---|---|
| `Brevo__ApiKey` | API key vừa tạo, chỉ lưu ở Render |
| `Email__From` | Email người gửi đã xác minh trên Brevo |
| `Email__FromName` | `Chấm công - Tống Nhật Bảo An` |
| `Auth__DebugReturnOtp` | `false` |

Giữ nguyên cấu hình database, JWT và migrations. Các biến `Smtp__...` không còn được code sử dụng, có thể xóa. Không commit API key vào GitHub hay đưa vào Flutter.

5. Push bản sửa backend lên GitHub rồi để Render deploy commit mới; lưu biến môi trường và redeploy nếu cần.
6. Chờ dịch vụ Live. Test `/api/auth/login` trên Swagger hoặc đăng nhập trong app. Thành công trả `challengeId`, `debugCode` rỗng/null và nhận email OTP. Nhập OTP để lấy token.

Email nhận là email đã lưu trong tài khoản nhân viên/database. `Seed__AdminEmail` chỉ được dùng khi tạo admin đầu tiên; thay biến này không cập nhật admin đã tồn tại. Cần dùng địa chỉ nhận mà bạn thực sự truy cập được.

## Khi chưa gửi được

API trả 503 với trường `error` tiếng Việt; Flutter hiện có sẵn xử lý trường này. Xem Application logs → Live tail:

- Configuration missing: thiếu `Brevo__ApiKey` hoặc `Email__From`.
- HTTP 401/403: kiểm tra API key, quyền gửi và trạng thái tài khoản.
- HTTP 400: kiểm tra người gửi đã xác minh và cấu hình email.
- HTTP 429: kiểm tra hạn mức/rate limit trong Brevo.
- Timeout/connection failed: lỗi kết nối HTTPS, thử lại sau.
- Accepted by Brevo: nhà cung cấp đã nhận yêu cầu, chưa đảm bảo thư vào Inbox; kiểm tra Spam và transactional logs bên Brevo.

Không tự động gửi lại khi timeout để tránh email trùng. OTP của lần đăng nhập gửi thất bại được vô hiệu hóa. Đăng ký mới thất bại khi gửi email sẽ được gỡ bản ghi vừa tạo để người dùng đăng ký lại. Tài khoản chưa xác minh được tạo bởi bản code cũ không tự được dọn.

`Auth__DebugReturnOtp=true` chỉ có hiệu lực trong Development để test local; Production luôn gửi OTP thật.

## Kiểm tra local không gửi thư thật

```powershell
dotnet build WebAPI_TongNhatBaoAn
dotnet run --project tool/OtpEmailChecks
```

Bộ kiểm tra giả lập HTTP: thành công, sai khóa, quá hạn mức, timeout, lỗi mạng và thiếu cấu hình. Kiểm tra gửi thật cần API key và người gửi đã xác minh.

Tham khảo: https://developers.brevo.com/docs/send-a-transactional-email
