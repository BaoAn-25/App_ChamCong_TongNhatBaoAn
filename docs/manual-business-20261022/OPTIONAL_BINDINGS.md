# Các chỗ hiển thị cũ nằm ngoài phạm vi model/service

Bộ chính không sửa `home_page.dart`, `app_controller.dart` hay thêm widget. Các biểu thức dưới đây chỉ hướng dẫn nối dữ liệu khi bạn dán thủ công. `optional-integration/lib/ui/stats_page.dart` đã có toàn bộ phần nối thống kê để khỏi tự ghép getter.

## Dashboard: trạng thái và nhân viên hoạt động

Model thay thế đã có `Attendance.statusLabel` và `Employee.emailVerified/approvalStatus`.

Ở vị trí đang suy luận “Đã hoàn tất” bằng `myTodayRecord.checkOut != null`, dùng giá trị trạng thái:

```dart
final todayStatus = myTodayRecord == null
    ? 'Chưa vào ca'
    : myTodayRecord.statusLabel;
```

Đưa `todayStatus` vào Text hiện có. Không dùng việc CheckOut khác null để kết luận ca tự đóng là ca đã hoàn tất. Khi hiển thị giờ ra của auto-close, ghi rõ đây là mốc tự đóng ước tính qua `a.explanation`, không trình bày như giờ ra đã xác thực.

Số nhân viên hoạt động ở Dashboard:

```dart
final activeEmployeeCount = c.data.employees.where((e) =>
    e.active && e.emailVerified && e.approvalStatus == 'Approved' &&
    (e.role == 'employee' || e.role == 'manager')).length;
```

Thay cho biểu thức cũ `e.active && !e.isStaff` vì biểu thức cũ loại nhầm Manager và chưa xét chờ duyệt. Số chuẩn toàn công ty cũng nằm trong response `StatisticsRepository.company(...)["activeEmployees"]`.

Thời gian trong lịch sử vẫn dùng `clock(a.checkIn)`/`clock(a.checkOut)` vì model đã parse UTC thành giờ địa phương. Không tự cộng thêm 7 giờ vào clock.

## Đơn từ: giữ hai nguồn dữ liệu khác nhau

```dart
final mine = await c.requestRepo.mine();
final pendingReview = c.isStaff
    ? await c.requestRepo.pendingReview()
    : <WorkRequest>[];
```

Trang “Đơn của tôi” lấy `mine`; nơi xử lý “Cần duyệt” lấy `pendingReview`. Nếu dùng controller cũ chưa có hai nguồn, có thể lưu chúng vào hai field riêng thay vì đổi `list()` thành một danh sách gộp. Bộ chính không tự tạo tab/chọn trang vì bạn không cho sửa widget. Trong khi chưa nối, hàng chờ duyệt vẫn có thể kiểm tra và xử lý bằng Swagger.

Mỗi lần review gửi đúng version mới nhất trả từ API. Refresh hàng chờ sau khi duyệt; không suy ra thành công chỉ bằng cách đổi trạng thái tạm trên client.

## Trạng thái sau đăng ký

Luồng hiện có có thể tiếp tục gọi `AuthService.verifyEmail(...)`. Sau xác minh, nội dung phù hợp để đặt vào thông báo hiện có là “Email đã xác minh. Vui lòng chờ Admin duyệt tài khoản.” Không thông báo đăng nhập thành công hoặc đã được phép chấm công. Backend từ chối login/refresh/face-login khi chưa Approved.
