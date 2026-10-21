# Giai đoạn Web API — chưa cấu hình / chưa triển khai

Theo yêu cầu, hoàn thiện và thử app local trước, sau đó triển khai chung một API.
Toàn bộ app và việc cấu hình API do Bảo An tự thực hiện, không phân chia công việc cho nhóm. Bảo An kết nối app của mình với API và dữ liệu thật trước, sau đó cung cấp API cho các bạn sử dụng.
Backend không bị đề ràng buộc ngôn ngữ; đề xuất ASP.NET Core Web API + PostgreSQL để tận dụng kiến thức C# của nhóm. Đây là lựa chọn kiến trúc, chưa cài SDK hay provision hosting.

Tên project backend `WebAPI_TongNhatBaoAn`; database `AppChamCong_TongNhatBaoAn`.
4 app dùng chung HTTPS base URL. Không dùng `localhost` trên điện thoại để trỏ máy chủ của bạn; localhost là chính điện thoại.

## Hợp đồng dự kiến

| Method / route | Quyền | Mục đích |
|---|---|---|
| POST /api/auth/register | Public có rate limit | Email, username, password, name; role luôn Employee |
| POST /api/auth/verify-email | Public có challenge | Xác minh email đăng ký |
| POST /api/auth/login | Public có rate limit | Kiểm tra mật khẩu, gửi OTP, trả challengeId; chưa cấp access token |
| POST /api/auth/verify-otp | Public có challenge | OTP có TTL, giới hạn thử, dùng một lần; trả token sau thành công |
| POST /api/auth/face/enroll | Đã xác thực gần đây | Đăng ký mẫu khuôn mặt gắn với chính nhân viên; cần thiết kế lưu trữ dữ liệu sinh trắc trước triển khai |
| POST /api/auth/face/login | Challenge ngắn hạn có rate limit | Phương thức đăng nhập bổ sung; chỉ cấp phiên sau xác minh danh tính, không tin cờ matched từ app |
| POST /api/auth/refresh, /logout | Phiên hợp lệ | Luân chuyển / thu hồi refresh token |
| GET /api/me | Đã đăng nhập | Hồ sơ và role từ server |
| GET, POST /api/employees | Admin | Danh sách / thêm nhân viên |
| PATCH, DELETE /api/employees/{id} | Admin | Sửa / xóa nếu không có lịch sử |
| GET /api/shifts | Theo quyền | Danh sách ca cần thiết |
| POST, PATCH, DELETE /api/shifts[/{id}] | Admin | CRUD ca |
| PUT /api/employees/{id}/shift | Admin | Phân ca |
| GET, PUT /api/office | GET chỉ dữ liệu công khai; PUT Admin | Tọa độ / bán kính; không trả khóa ký QR |
| POST /api/office/qr | Admin | QR ngắn hạn, ký bằng secret chỉ có ở server |
| POST /api/attendance/check-in | Employee | QR, lat/lng, accuracy, capturedAt, idempotencyKey |
| POST /api/attendance/check-out | Employee | Ghi giờ ra; server lấy user từ token |
| GET /api/attendance?from=&to= | Employee của mình, Admin toàn bộ | Phân trang / lọc / thống kê |
| GET, POST /api/requests | Theo quyền | Danh sách / tạo đơn của mình |
| PATCH, DELETE /api/requests/{id} | Chủ đơn pending | Sửa / xóa |
| POST /api/requests/{id}/review | Admin khác chủ đơn | Duyệt hoặc từ chối, optimistic concurrency |
| GET /health/live, /health/ready | Theo cấu hình vận hành | Tiến trình / khả năng truy cập DB |

Schema cơ bản: Employees, Shifts, Office, Attendance, WorkRequests, OtpChallenges, RefreshTokens, AuditEvents. Mọi ngày giờ lưu UTC; ngày làm việc diễn giải theo Asia/Ho_Chi_Minh. Hash password ở backend, không nhận passwordHash từ app.

## Chuyển đổi từ local

`DataStore` hiện lưu snapshot local cho prototype. **Không triển khai API bằng cách GET/PUT toàn bộ snapshot** vì sẽ làm lộ nhân viên, hash mật khẩu và khóa QR. Cần service theo nghiệp vụ (AuthService, EmployeeRepository, AttendanceRepository, RequestRepository), endpoint có kiểm tra quyền. UI gọi qua controller hiện tại; controller chuyển sang gọi các service này.

- Tách chế độ local/API rõ ràng, không tự fallback local khi server chết (tránh hai bộ dữ liệu không khớp).
- Token lưu secure storage, hết hạn điều hướng đăng nhập. Không đóng gói secret DB/SMTP/QR trong APK.
- Server kiểm tra QR, khoảng cách, phân ca, OTP, role và thời gian. Kiểm tra GPS client chỉ hỗ trợ UX; GPS có thể giả mạo nên không quảng cáo chống gian lận tuyệt đối.
- Unique constraint/transaction chặn hai request chấm công đồng thời. Check-in và check-out là lệnh riêng, không toggle tự động ở API.
- Retry có idempotencyKey. Không tự retry lệnh ghi không có idempotency.
- Admin đầu tiên tạo bằng seed server dùng secret môi trường, không mở đăng ký Admin công khai.
- Migrate dữ liệu local chỉ qua quy trình import Admin được xác nhận; không upload hash/secret prototype làm production.

## Chuẩn bị buổi thầy kiểm tra

Không dịch vụ nào bảo đảm không bao giờ gián đoạn. Chọn hosting có tiến trình chạy liên tục, tránh gói ngủ khi không có truy cập, DB lưu bền vững, HTTPS, log và sao lưu. Chọn nhà cung cấp/gói ở bước cấu hình sau khi biết ngân sách.

1. Deploy trước buổi kiểm tra, chạy migration, healthcheck và thử cả đọc/ghi.
2. Test 4 thiết bị bằng Wi-Fi và 4G, cùng thấy nhân viên, ca, QR, đơn và công.
3. Kiểm tra SMTP/email thật, spam, OTP hết hạn, token hết hạn và mạng bị ngắt.
4. Có phương án chạy API + DB trên laptop trong LAN để demo nếu Internet gặp sự cố; dùng cấu hình riêng, không giả vờ dữ liệu local đang đồng bộ server.
5. Build APK đã kiểm tra, không cập nhật thư viện sát giờ thuyết trình. Commit pubspec.lock khi đã resolve và test.
