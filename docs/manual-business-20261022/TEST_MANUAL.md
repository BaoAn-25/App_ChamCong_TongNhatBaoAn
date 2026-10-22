# Test sau khi dán code

Chạy trên DB thử/nhánh thử của bạn trước; không đổi đồng hồ server sản xuất để test. Dùng Swagger `/swagger`, token Admin/Manager/Employee khác nhau. Ghi lại response status và JSON; xóa token/mật khẩu khỏi ảnh/log chia sẻ.

| Mục | Thao tác | Kết quả mong đợi |
|---|---|---|
| Schema | Kiểm tra EF history và cột mới sau migrate | Có AttendanceBusinessRules; không 500 do thiếu cột |
| Múi giờ | Chấm lúc 12:50 VN; xem DB UTC, API và điện thoại | API 05:50Z, điện thoại VN 12:50; không sửa DB thêm 7h |
| Chuỗi sai | POST capturedAt không Z/offset | 400, không tạo attendance/QR redemption |
| Đăng ký | Gửi payload role=admin vào public register | Không có role trong DTO; DB employee + PendingApproval |
| Xác minh | Gửi OTP email đúng; thử đăng nhập trước duyệt | EmailVerified=true nhưng login 403, không phát OTP đăng nhập/JWT |
| Duyệt signup | Admin GET registrations/pending; POST review với version | Approved hoặc Rejected; account không tự chọn role |
| Quyền | Employee gọi registrations/review hoặc statistics/company | 403 |
| Đăng nhập | Approved + mật khẩu đúng + OTP đúng | Token; role đúng; OTP sai/hết hạn/dùng lại bị từ chối |
| Bị khóa | Khóa account đã có JWT/refresh/face profile | JWT request, refresh và face login không dùng được |
| Ca | PATCH ca 08:00–17:00 nghỉ60/grace5/earlyGrace5 | DTO trả đủ trường; PATCH chỉ name giữ nguyên break60 |
| Ca sai | Break bằng độ dài ca; start=end; minute ngoài 0–1439 | 400 |
| Vào sớm | Ca08:00: vào06:59 và07:00 | 06:59 bị409; 07:00 được phép nếu QR/GPS/face đúng |
| Vào sau ca | Ca08:00–17:00, vào17:00 | 409 |
| Ra ngay | Vào xong ra ngay hoặc sau29phút | 409; ca còn mở; không mất proof/QR do giao dịch rollback |
| Ra hợp lệ | Ra sau ít nhất30phút, QR mới, proof mới nếu enrolled | Thành công; số phút net không âm |
| Đi trễ | Vào08:05 và08:05:01, grace5 | 0 phút và1 phút trễ |
| Về sớm | Ra16:55 và16:54, earlyGrace5 | 0 phút và1 phút sớm |
| Giờ nghỉ | Vào08:00, ra17:00, nghỉ60 | NetMinutes480, hours8 |
| Qua đêm | Ca22:00–06:00; vào tối, ra sáng | ScheduledEnd là sáng hôm sau; không bị tự đóng giữa ca |
| Gần 00:00 | Ca00:30, vào23:45 hôm trước, early60 | Chọn đúng ca bắt đầu hôm sau |
| Tự đóng | Bản ghi test không ra, AutoCloseAt đã qua | Worker/list/stats/punch đóng, QuenCheckOut, IsAutoClosed=true, net0 |
| Render ngủ | Bản ghi quá hạn rồi gọi API sau khi thức | Catch-up đóng được, không đợi thêm một ngày |
| GPS | Sai số50 và50.1; mock=true; ngoài100m | 50 có thể được; các trường hợp còn lại bị từ chối |
| GPS giả thời gian | CapturedAt cũ hơn60s hoặc tương lai hơn5s | 400 |
| QR | Lấy QR, dùng trước hạn; dùng đúng lúc issued+60s | Trước hạn hợp lệ; tại hạn bị từ chối |
| QR dùng lại | Cùng user/cùng QR nhưng request key khác | 409, không thêm ca; user khác vẫn có lượt riêng |
| Mạng retry | Gửi lại cùng operation và idempotencyKey đã thành công | Trả bản ghi cũ, không tiêu thụ QR lần hai |
| Đồng thời | Gửi2check-in/checkout hoặc2duyệt đồng thời | Tối đa1 ghi thành công; bản còn lại409 hoặc trả kết quả idempotent; không ghi đè |
| Ngày phép | Nghỉ thứ Sáu–thứ Hai với loại trừ T7/CN | days2; chỉ cuối tuần không có ngày phép thì400 |
| Trùng phép | Tạo đồng thời2đơn nghỉ trùng của cùng người | Một đơn bị409 |
| Đơn của tôi | GET mine khi đăng nhập từng vai trò | Chỉ đơn chính người đó |
| Cần duyệt | Manager GET pending-review | Chỉ pending Employee khác; không đơn mình/Admin/Manager |
| Duyệt vượt quyền | Manager POST review đơn Admin; Admin review chính mình | 403 |
| Duyệt Admin | Admin thứ hai review đơn Admin thứ nhất | Được nếu pending, version đúng; có reviewedBy/reviewerName/reviewedAtZ |
| Duyệt cũ | Review lặp hoặc version cũ | 409 |
| Thống kê0 | Không có ca/hết ca chưa ra/ra net0 | Không “Xuất sắc”, không xuất hiện bảng xếp hạng0giờ |
| Thống kê100 | Ca đủ480phút, đúng giờ, checkout thật | 100 điểm; đối chiếu mine/company không trộn scope |
| Phạm vi công ty | Có Admin, locked, pending và active Employee/Manager | Chỉ approved+verified+active Employee/Manager tính activeEmployees/ranking |
| Dữ liệu cũ | Chạy preview lịch sử sau migration | OriginalCheckIn/Out giữ nguyên; BatThuong chờ đối soát |
| Dọn test | Chạy03-data-cleanup mặc định | Có preview, cuối cùng rollback; account Admin không bị chọn |

Test mốc giờ dài có thể dùng TimeProvider giả trong môi trường integration, hoặc tạo ca phù hợp thời điểm hiện tại. Không nới MinSessionMinutes/GPS/OTP trong production chỉ để quay demo. Test worker có thể đặt AutoCloseAt của **một bản ghi test** về quá khứ trong DB thử; không sửa giờ toàn máy hay mọi bản ghi.

Sau khi dán model/service, test lại toàn bộ đường camera → face proof → QR+GPS → punch. Bộ này giữ face matcher và OTP Brevo sẵn có nhưng chưa thực hiện test mạng thật với các dịch vụ đó.
