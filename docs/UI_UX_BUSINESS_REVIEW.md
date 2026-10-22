# Rà soát UI/UX và nghiệp vụ — 22/10/2026

## Thay đổi theo màn hình

| Màn hình | Thay đổi |
|---|---|
| Đăng nhập / đăng ký / OTP | Khóa trường khi gửi; hỗ trợ autofill tài khoản; bỏ nhãn máy chủ “sẵn sàng” không dựa trên kiểm tra thực tế. Giữ xác nhận mật khẩu, gửi lại OTP và báo lỗi tại chỗ. |
| Khung ứng dụng | Điều hướng điện thoại còn 4 mục; Thống kê, Đơn từ, Tài khoản nằm trong Tiện ích. Màn rộng giữ NavigationRail. Nút và ô nhập đồng nhất, vùng bấm tối thiểu 48px. |
| Tổng quan | Có trạng thái đồng bộ thật, thời điểm cập nhật và tải lại; không báo đang kết nối khi dữ liệu tải lỗi. Ngày hiện tại tính theo giờ Việt Nam. |
| Quản lý nhân viên / ca / văn phòng | Hướng dẫn thứ tự thiết lập; hành động của Section xuống dòng riêng để đỡ chật. Giữ kiểm tra quyền Admin/Manager. Sửa cập nhật ca trong bộ nhớ sau phân ca. |
| Bảng công | Kéo để tải lại, hướng dẫn tìm/lọc/xem chi tiết, hiển thị “Thiếu giờ ra” khi ca thực sự đã kết thúc. |
| Đơn từ | Hướng dẫn quyền sửa/xóa; chọn ngày bằng lịch thay cho gõ chuỗi; lý do nhập nhiều dòng. |
| Tài khoản / sinh trắc | Hướng dẫn kiểm tra email và thiết bị; xác thực sinh trắc không nhận PIN thay thế. Chỉ có sinh trắc thiết bị, không đối sánh khuôn mặt nhân viên trên server. |
| Chấm công / quét QR | Luồng hướng dẫn ngắn; giữ lỗi tại chỗ; cập nhật GPS sau hộp thoại sinh trắc; chống bấm gửi lặp. Thiết bị chưa bật sinh trắc vẫn chấm bằng GPS + QR + phiên đăng nhập. |
| Thống kê | Thiết kế lại thẻ số liệu, biểu đồ, bộ lọc tuần/tháng và cá nhân/toàn bộ. Nêu rõ công thức và giới hạn. Không xếp hạng nhân viên theo số giờ làm. |

## Lỗi đã sửa trong mã nguồn

| Lỗi | Cách xử lý |
|---|---|
| Bỏ ngày 29–31 ở biểu đồ tháng | Chia nhóm ngày đủ 4 hoặc 5 nhóm theo số ngày thực tế. |
| Ca đang làm bị coi là quên chấm ra | Chỉ cảnh báo khi chưa ra và đã qua giờ kết thúc ca. |
| Chưa có dữ liệu vẫn chấm 100 điểm | Hiển thị chưa có dữ liệu; thay điểm tự đặt bằng tỷ lệ đúng giờ có công thức. |
| Số liệu bị giới hạn 100 dòng | Tải các trang API đến hết; loại bản ghi trùng ID. Server sắp xếp ổn định theo thời gian và ID. |
| Kỳ báo cáo phụ thuộc múi giờ điện thoại hoặc chứa dữ liệu tương lai | Tính kỳ theo UTC+7, có mốc kết thúc, loại giờ vào trong tương lai. |
| Đồng bộ lỗi nhưng báo thành công và trộn dữ liệu cũ/mới | Chỉ thay dữ liệu khi toàn bộ nhóm tải thành công; giữ dữ liệu cũ cùng thông báo lỗi. |
| Một số thao tác quản lý gửi lặp | Chặn khi đang thực hiện và hiện tiến trình. |
| Gọi đồng thời nhiều lần refresh token | Dùng chung tác vụ refresh đang chạy. Lỗi mạng không tự xóa phiên. |
| Khóa/đổi quyền tài khoản nhưng JWT cũ còn quyền | Khi xác thực JWT, đối chiếu tài khoản đang hoạt động, đã xác minh và vai trò hiện tại trong DB. |
| Chấm vào sau giờ kết thúc ca | Backend trả 409, yêu cầu giải trình. |
| Khoảng lọc ngày đảo ngược | Backend từ chối rõ ràng. |

## Kết luận về “AI”

Phiên bản này dùng thuật toán thống kê và quy tắc, không gọi mô hình AI. Đã đổi nhãn thành “Nhận xét tự động”. Không thể khẳng định là tính năng chưa app nào có hoặc tự động đạt điểm sáng tạo.

Giờ công chỉ cộng ca đã chấm ra, chưa trừ nghỉ; tỷ lệ đúng giờ dựa trên ca đã chấm vào. Không tự suy ra vắng mặt, tính lương, năng suất hoặc sức khỏe. Thống kê nhóm nói về toàn bộ nhóm, có bộ lọc cá nhân. Ca qua đêm được nhóm theo ngày chấm vào tại Việt Nam, không chia giờ sang hai ngày.

## Bằng chứng kiểm tra

- Backend build: đạt, 0 lỗi/0 cảnh báo.
- Kiểm tra thuần Dart `tool/check_analytics.dart`: 10 trường hợp đạt (ngày 31, năm nhuận, ca đang làm/quá giờ, ranh giới UTC+7, phân tách nhân viên, kỳ tuần, dữ liệu trống/tương lai, giờ âm).
- Có bộ kiểm tra `test/attendance_pagination_test.dart` và `test/ui_review_test.dart` cho tải nhiều trang và điều hướng 6 trang trên màn 360px với 3 vai trò.
- Chưa chạy được các Flutter widget tests: công cụ bị chặn ghi tệp telemetry khi biên dịch hook `objective_c`. Có thử SDK tạm dưới `.dart_tool` nhưng vẫn bị chặn; không thay quyền hoặc sửa SDK gốc.
- Chưa xác nhận render trực quan, QR/camera/GPS/sinh trắc trên điện thoại, gửi Gmail thật, hoặc dữ liệu thật trên Render. Không có thay đổi server hay push GitHub trong lượt này.

## Giới hạn nghiệp vụ cần biết

- Chưa có lịch tuần/ngày lễ/nhiều ca trong ngày để kết luận nhân viên vắng hoặc đủ giờ.
- GPS và sinh trắc phía điện thoại không phải bằng chứng chống gian lận tuyệt đối. Backend không xác minh bằng chứng sinh trắc bằng chữ ký thiết bị.
- Nhiều trang dữ liệu được tải tuần tự, chưa phải một snapshot DB duy nhất; khi người khác chấm công đồng thời nên tải lại trước khi xuất báo cáo.
- Cần kiểm thử đồng thời 2 máy ở các thao tác chấm ra, duyệt đơn, refresh token trước khi xem là sẵn sàng sử dụng thực tế.
- Các test local-mode cũ trong `domain_test.dart`/`widget_test.dart` chưa đại diện cho kiến trúc API. Chạy các test chỉ định trong hướng dẫn mới, không khẳng định toàn bộ suite cũ đạt.

Xem `TEST_FULL_APP.md` để kiểm thử đầu cuối.
