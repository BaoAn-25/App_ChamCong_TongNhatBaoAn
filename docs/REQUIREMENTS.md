# Đối chiếu đề kiểm tra — Nhóm 09

Tên thư mục: `AppChamCong_TongNhatBaoAn`.
Tên package Dart: `app_cham_cong_tong_nhat_bao_an` (Dart yêu cầu lowercase_with_underscores).
Tên Web API dự kiến: `WebAPI_TongNhatBaoAn`.
Tên database dự kiến: `AppChamCong_TongNhatBaoAn`.
Không đổi thành tên chung khi nộp. Các thành viên phải hỏi thầy quy định tên cá nhân áp dụng cho từng bản nộp hay cho cả nhóm.

| Yêu cầu | Triển khai giai đoạn local | Điều kiện hoàn tất bài nộp |
|---|---|---|
| Đăng ký email | Nhập và kiểm tra email, chống trùng, tạo tài khoản nhân viên | Gửi email xác minh từ backend |
| Username + password + OTP | PBKDF2 mật khẩu; OTP ngẫu nhiên, 2 phút, tối đa 5 lần sai, dùng một lần; hiện mã demo | Email OTP thật, rate limit và kiểm tra server; tuyệt đối bỏ mã demo |
| Phân quyền | Admin/Employee, dashboard và kiểm tra lệnh theo vai trò | Backend xác thực mọi endpoint; không tin role phía Flutter |
| CRUD 4,5đ | Nhân viên, ca làm, đơn từ; tìm kiếm, phân ca, khóa tài khoản, duyệt đơn | Kiểm thử CRUD giữa nhiều máy, giữ khóa ngoại và lịch sử |
| Chức năng b | GPS thật; chia sẻ đường dẫn vị trí qua bảng chia sẻ hệ thống | Demo Android có cấp quyền |
| Chức năng a | Đã chọn đăng nhập bằng khuôn mặt; **chưa triển khai xác thực khuôn mặt** | Đăng ký mẫu gắn với nhân viên, đối sánh danh tính và xử lý thất bại; phát hiện mặt đơn thuần không đạt mục này |
| Chức năng e | Camera quét QR, Admin hiện QR động; nhập mã là lối thử nghiệm riêng | Demo quét camera thật; backend phát và kiểm tra QR dùng chung |
| Tính năng đề xuất 1đ | Giải thích đi trễ, ra sớm, quên giờ ra; đơn giải trình liên quan nghiệp vụ | Trao đổi với thầy về tính mới; chưa có căn cứ nói mọi app khác đều chưa có |
| Giao diện / cả nhóm chạy 1đ | Material 3, tiếng Việt, responsive, điều hướng theo vai trò, hướng dẫn setup | Chạy trên đủ 4 máy, kết nối chung API và kiểm tra điện thoại |

Chỉ có Admin và Nhân viên vì đây là app nội bộ; không tự thêm vai trò khách hàng không có nghiệp vụ.

## Quy tắc hiện tại

- Một ca định kỳ cho mỗi nhân viên. Chưa có lịch nhiều ca/ngày, lịch tuần hay lịch ngày lễ.
- Ca qua đêm kết thúc vào ngày tiếp theo. Trước giờ kết thúc ca đêm, chấm vào thuộc ngày trước.
- Vào và ra đều cần GPS mới trong 60 giây, sai số không quá 80 m, không báo mock, trong bán kính văn phòng và QR hợp lệ.
- QR HMAC đổi theo phút; chấp nhận phút hiện tại và phút trước. Khóa nằm local chỉ để thử, không chống được người kiểm soát thiết bị.
- Không cho ca đã hoàn tất chấm vào lại cùng ngày kết thúc ca. Bản ghi đang mở cần chấm ra trước khi vào ca mới.
- Nghỉ phép đã duyệt chặn chấm vào ngày đó. Đơn duyệt không tự sửa bảng công; giải trình giữ lý do và phản hồi.
- Không xóa nhân viên đã có công/đơn; khóa tài khoản thay thế. Không xóa ca đang được phân công.
- Không được tự khóa Admin đang đăng nhập, tự duyệt đơn, sửa/xóa đơn đã được duyệt hoặc từ chối.
- Tổng giờ là chênh lệch vào–ra của ca hoàn tất, chưa trừ giờ nghỉ, chưa tính lương hoặc làm thêm.
- Không có dữ liệu mẫu trong production. Dữ liệu giả chỉ tồn tại trong file test.

## Cách thực hiện đã chốt với Bảo An

Bảo An tự làm toàn bộ frontend Flutter, các chức năng và tự cấu hình Web API. Không phân chia công việc phát triển cho các thành viên khác. Làm và kiểm tra các chức năng app trước, sau đó nối dữ liệu Web API thật vào app của Bảo An. Khi API đã hoạt động, cung cấp base URL và hướng dẫn tích hợp cho các bạn trong nhóm sử dụng chung. Không chia sẻ mật khẩu quản trị, mật khẩu DB hoặc secret SMTP.

## Ba chức năng lựa chọn: a + b + e

| Mục đề | Chức năng | Vai trò trong app chấm công |
|---|---|---|
| a | Đăng nhập bằng khuôn mặt | Xác thực nhân viên đã đăng ký mẫu, hỗ trợ giảm việc dùng hộ tài khoản; không cam kết chống giả mạo tuyệt đối |
| b | Chia sẻ vị trí | Nhân viên chủ động chia sẻ vị trí làm việc; vị trí GPS còn được dùng đối chiếu phạm vi chấm công |
| e | Quét QR | Quét QR văn phòng/điểm chấm công, kết hợp vị trí và tài khoản để ghi nhận giờ vào/ra |

Vân tay, NFC, QR, Barcode đều nằm trong **cùng mục e**, không được tính thành nhiều mục để đủ ba. Không chọn đo chuyển động, gọi video nhóm hoặc dịch realtime vì chưa có nghiệp vụ cốt lõi tương ứng ở app này.

Luồng dự kiến: đăng ký tài khoản → đăng ký mẫu khuôn mặt sau khi đã xác thực tài khoản → đăng nhập bằng khuôn mặt → chấm công bằng QR và vị trí. Luồng username + password + OTP theo mục 2 vẫn giữ đầy đủ; đăng nhập khuôn mặt là phương thức bổ sung.

Mục a đang là hạng mục cần triển khai tiếp, không tính là đã hoàn thành. Camera chụp ảnh, nhận diện vùng mặt hay hộp thoại sinh trắc học của hệ điều hành không tự động chứng minh đã đối sánh đúng nhân viên. Cần kiểm thử mẫu đúng/sai người, thiếu sáng, nhiều mặt, ảnh chụp lại và cơ chế khôi phục. Trước khi đánh giá chống giả mạo cần triển khai và kiểm thử liveness riêng.
