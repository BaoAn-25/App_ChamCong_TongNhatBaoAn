# Kiểm thử toàn bộ app trên điện thoại

## Chuẩn bị

Push code đã kiểm tra, deploy backend mới lên Render và chờ Live. Kiểm tra Brevo API key/email người gửi đã xác minh. Cắm điện thoại, mở terminal ở gốc dự án:

```powershell
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/attendance_pagination_test.dart test/ui_review_test.dart test/models_test.dart
flutter run
```

Các lệnh chạy trong terminal của bạn có thể không gặp giới hạn quyền của công cụ. Nếu test thất bại, giữ nguyên lỗi để sửa; không bỏ qua rồi đánh dấu đạt.

Chuẩn bị Admin, Manager và 2 tài khoản nhân viên dùng Gmail do người test kiểm soát. Dùng dữ liệu thử có tên `TEST_...`, không xóa dữ liệu chấm công thật. Không gửi mật khẩu, OTP hay API key trong báo cáo.

## Checklist — ghi Đạt/Lỗi/Chưa thử cho từng dòng

| ID | Thao tác | Kết quả cần đạt |
|---|---|---|
| AUTH01 | Đăng ký email mới | Nhận Gmail OTP; nhập đúng mới xác minh được. |
| AUTH02 | Email sai, mật khẩu ngắn, xác nhận khác | Báo lỗi, giữ dữ liệu đã nhập. |
| AUTH03 | Đăng ký trùng tài khoản đã xác minh | Bị từ chối, không thay mật khẩu/vai trò. |
| AUTH04 | Hủy xác minh rồi đăng ký lại đúng thông tin | Được nhận OTP mới; sai mật khẩu cũ không được tiếp tục. |
| AUTH05 | Gửi lại OTP, nhập mã sai 5 lần / hết hạn / đã dùng | Mã không hợp lệ bị từ chối; xin mã mới để thử lại. |
| AUTH06 | Đăng nhập đúng/sai mật khẩu | Đúng mới vào bước OTP; chưa OTP không vào Dashboard. |
| AUTH07 | Dùng OTP đăng ký cho đăng nhập | Bị từ chối vì khác mục đích. |
| AUTH08 | Đăng xuất, mở lại app | Không tự vào phiên vừa đăng xuất. |
| ROLE01 | Admin, Manager, Employee đăng nhập riêng | Đúng chức năng theo quyền; nhân viên không thấy quản lý người khác. |
| ROLE02 | Admin khóa nhân viên đang đăng nhập máy khác | Yêu cầu API tiếp theo bị từ chối; không dùng JWT cũ để tiếp tục. |
| ROLE03 | Hạ quyền Manager đang mở app | API quyền cũ bị từ chối; làm mới phiên và tải lại theo quyền mới. |
| CRUD01 | Thêm/sửa/tìm nhân viên | Dữ liệu lưu thật, máy khác tải lại nhìn thấy; email/username trùng bị chặn. |
| CRUD02 | Xóa nhân viên có bảng công/đơn | Bị chặn, dùng khóa tài khoản; không mất lịch sử. |
| CRUD03 | Tạo/sửa/xóa ca, thử giờ bằng nhau và dung sai ngoài 0–60 | Dữ liệu sai bị chặn; ca đang được gán không xóa được. |
| CRUD04 | Phân ca / bỏ phân ca | Hiển thị đúng sau lưu và sau tải lại. |
| OFFICE01 | Đặt vị trí, bán kính đúng/sai | Chấp nhận tọa độ hợp lệ và bán kính 20–5000m. |
| PUNCH01 | GPS đúng + QR mới + đã phân ca | Chấm vào thành công, chấm ra thành công, giờ do server ghi nhận. |
| PUNCH02 | Tắt GPS/từ chối quyền/ngoài bán kính/sai số lớn | Thông báo rõ, không tạo bản ghi. |
| PUNCH03 | QR hết hạn hoặc không đúng | Bị từ chối, quét lại mã mới. |
| PUNCH04 | Chưa phân ca / đã được duyệt nghỉ / ca đã kết thúc | Chặn chấm vào và nêu lý do. |
| PUNCH05 | Bấm nhanh nhiều lần hoặc dùng 2 máy chấm cùng lúc | Không sinh hai ca mở hoặc bản ghi trùng; tải lại kiểm tra. |
| PUNCH06 | Máy không có sinh trắc hoặc chưa bật | Vẫn dùng GPS + QR với phiên đăng nhập hợp lệ. |
| BIO01 | Kích hoạt sinh trắc sau đăng nhập OTP | Chỉ cho xác thực sinh trắc thật; PIN không thay thế. |
| BIO02 | Hủy/sai sinh trắc/refresh hết hạn | Không đăng nhập nhanh; có thể quay về mật khẩu + OTP. |
| SHARE01 | Chia sẻ GPS rồi mở đường dẫn | Vị trí hiển thị đúng; chỉ chia sẻ khi người dùng chọn. |
| REQUEST01 | Tạo đơn bằng bộ chọn ngày, lý do <10 ký tự, ngày đảo | Dữ liệu sai bị chặn; đơn hợp lệ xuất hiện chờ duyệt. |
| REQUEST02 | Sửa/xóa đơn đang chờ, thử đơn đã xử lý | Chỉ chủ đơn đang chờ được sửa/xóa. |
| REQUEST03 | Duyệt/từ chối và thử tự duyệt | Quyền đúng được xử lý; tự duyệt bị chặn. |
| REQUEST04 | Hai người duyệt cùng một đơn | Một kết quả được ghi, người còn lại nhận báo xung đột. |
| HISTORY01 | Tìm kiếm, lọc ngày, xem chi tiết, xuất CSV | Bản ghi phù hợp bộ lọc; giờ/nhân viên đúng; tệp mở được. |
| STATS01 | Tuần/tháng và cá nhân/toàn bộ | Tổng ca/giờ khớp các bản ghi; nhân viên chỉ xem của mình. |
| STATS02 | Có dữ liệu ngày 29, 30, 31 và >100 bản ghi | Không mất các ngày cuối tháng hoặc dữ liệu sau dòng 100. |
| STATS03 | Ca chưa hết giờ và ca quá giờ chưa ra | Chỉ ca quá giờ được cảnh báo thiếu giờ ra. |
| STATS04 | Không có dữ liệu | Không tự cho 100 điểm; hiện trạng thái trống. |
| NETWORK01 | Tắt mạng rồi tải lại | Báo chưa cập nhật; giữ dữ liệu trước; không báo đã đồng bộ mới. |
| NETWORK02 | Token hết hạn khi tải nhiều API | Chỉ một yêu cầu refresh cùng lúc; lỗi mạng không tự xóa phiên. |
| UI01 | Màn nhỏ, phóng chữ, mở bàn phím, xoay ngang | Không tràn chữ/che nút; cuộn được; có thể quay lại. |
| UI02 | Duyệt 6 trang bằng menu Tiện ích | Đến đúng trang, bộ lọc tuần/tháng hoạt động. |
| TEAM01 | Cả 4 máy kết nối chung API | Đăng nhập tài khoản riêng, nhận Gmail riêng, dữ liệu đồng bộ sau tải lại. |

Các trường hợp thống kê cuối tháng/năm nhuận có thể dùng bộ test thuần Dart thay vì sửa đồng hồ hay database production:

```powershell
dart tool/check_analytics.dart
```

## Báo lỗi

Ghi: ID checklist → vai trò → màn hình → các bước → kết quả mong đợi → thực tế → thời điểm GMT+7 → ảnh hoặc log. Với lỗi API, gửi mã HTTP và exception đầu tiên trên Render Live tail. Che dữ liệu bí mật. Đừng kết luận chỉ từ dòng đỏ nếu các dòng tiếp theo vẫn chạy thành công.
