# AppChamCong_TongNhatBaoAn

Ứng dụng Flutter/Dart chấm công nhân viên — nhóm 09, môn Lập trình di động.

**Trạng thái: đã viết source giai đoạn local, chưa kết nối Web API. Chưa xác nhận build APK thành công.**
Email và OTP hiện là mô phỏng có ghi nhãn trong app. Dữ liệu không đồng bộ giữa các máy.

## Chức năng đã triển khai trong source

- Khởi tạo Admin lần đầu; đăng ký nhân viên bằng email/username/password.
- Đăng nhập hai bước: mật khẩu + OTP local hết hạn sau 2 phút, tối đa 5 lần sai.
- Hai giao diện Admin / Nhân viên; kiểm tra quyền ở controller.
- CRUD nhân viên, khóa tài khoản, tìm kiếm, phân ca; CRUD ca ngày / ca qua đêm.
- Chấm công vào/ra: GPS thật + QR động; chặn vị trí cũ, sai số cao, ngoài bán kính, QR hết hạn và ca đã hoàn tất.
- Chia sẻ vị trí bằng bảng chia sẻ hệ thống; camera quét QR.
- Tạo/sửa/xóa đơn chờ duyệt, Admin duyệt/từ chối, ngăn tự duyệt và sửa đơn đã xử lý.
- Bảng công, tìm kiếm, lọc ngày, sao chép CSV; giải thích đi trễ, ra sớm, thiếu giờ ra.
- Lưu dữ liệu local qua SharedPreferences; không tự thêm tài khoản hay công giả.

## Phạm vi và ba chức năng theo mục 5

Bảo An tự làm toàn bộ frontend, chức năng app và Web API; không chia việc phát triển cho nhóm. Sau khi app kết nối dữ liệu thật, Bảo An cung cấp API chung cho các bạn sử dụng.

Chọn **(a) đăng nhập bằng khuôn mặt + (b) chia sẻ vị trí + (e) quét QR**, gắn trực tiếp với xác thực nhân viên và chấm công đúng địa điểm. QR/vân tay/NFC/Barcode chỉ là các lựa chọn trong cùng mục e, không tính riêng thành nhiều mục.

**Đăng nhập bằng khuôn mặt chưa được triển khai.** Đây là tính năng cần làm tiếp; không coi camera phát hiện mặt là xác thực danh tính. Đã bỏ đo chuyển động vì không sát nghiệp vụ. Username + password + OTP vẫn giữ theo yêu cầu 2.

## Chạy trên máy

Mở đúng thư mục này trong Android Studio hoặc VS Code. Dùng Flutter 3.44.2 / Dart 3.12.2 trở lên tương thích, Android SDK và JDK 17 trở lên phù hợp Gradle. Lần đầu cần mạng để tải package, Gradle và Android artifacts.

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

Nếu nhiều thiết bị: `flutter run -d <device-id>`.
Xem giao diện trên trình duyệt: `flutter run -d chrome`. Web không thay thế kiểm thử camera/GPS trên Android thật. GPS và camera web cần localhost hoặc HTTPS và quyền trình duyệt.

```powershell
flutter build apk --debug
```

APK khi build thành công: `build/app/outputs/flutter-apk/app-debug.apk`.
Chưa phát hành production; cấu hình release mặc định còn dùng debug signing của Flutter.

## Demo local trên một máy

1. Mở app → **Thiết lập lần đầu** → tự tạo tài khoản Admin. Dùng mật khẩu ít nhất 8 ký tự. Không có tài khoản/mật khẩu mặc định.
2. Đăng nhập Admin → nhập OTP thử nghiệm hiển thị trên màn hình.
3. **Quản lý → Lấy GPS để thiết lập** → kiểm tra tọa độ, nhập tên văn phòng và bán kính phù hợp → Lưu. Nếu GPS sai số lớn, ra nơi thoáng và thử lại.
4. Tạo ca làm, thêm nhân viên (hoặc đăng ký nhân viên ở màn hình đăng nhập), dùng menu **Phân ca**.
5. **Hiển thị QR động → Sao chép mã để thử trên một máy**. Đăng xuất Admin, đăng nhập nhân viên.
6. Trong khoảng hiệu lực mã, vào **Chấm công**, lấy GPS mới, **Demo một máy: dán mã Admin**, xác nhận giờ vào. Đây chỉ là lối kiểm thử, chưa thay cho demo quét camera thật.
7. Để thử camera thật: hiển thị QR của chính bộ dữ liệu này trên một màn hình khác (ví dụ trình chiếu màn hình Admin rồi chuyển tài khoản nhanh). Mã của hai bản cài độc lập có khóa khác nhau nên không dùng chéo được. Demo nhiều máy đầy đủ cần bước API.
8. Thử **Chia sẻ vị trí**. Khi không chia sẻ, hủy bảng chia sẻ hệ thống.
9. Chấm giờ ra bằng GPS/QR mới. Xem **Bảng công**, lọc ngày và phần giải thích.
10. Tạo đơn → đăng xuất → Admin duyệt → đăng nhập nhân viên để xem phản hồi.
11. Đóng/mở app, đăng nhập lại để kiểm tra dữ liệu vẫn còn.

Không dùng tài khoản/mật khẩu công việc thật cho bản prototype. Dữ liệu chứa hash mật khẩu và khóa QR vẫn nằm trên thiết bị, chưa phải hệ thống chấm công triển khai thực tế.

## Cấu trúc

- `lib/domain/models.dart`: nhân viên, ca, bảng công, đơn từ, văn phòng; JSON và giải thích bất thường.
- `lib/domain/app_controller.dart`: kiểm tra nghiệp vụ và phân quyền; OTP demo, chấm công, duyệt đơn.
- `lib/data/local_store.dart`: hợp đồng lưu trữ và bản local. Snapshot chỉ dành cho local, không đưa nguyên snapshot lên API.
- `lib/ui/`: đăng nhập, dashboard, CRUD, bảng công, GPS/QR.
- `test/`: kiểm thử mô hình, nghiệp vụ và màn hình khởi tạo.
- `docs/REQUIREMENTS.md`: đối chiếu điểm đề bài, giới hạn nghiệp vụ, lựa chọn a + b + e và phạm vi Bảo An tự thực hiện.
- `docs/API_NEXT_PHASE.md`: thiết kế API dùng chung, quyền endpoint, kế hoạch triển khai.
- `docs/TEST_CHECKLIST.md`: kiểm thử thiết bị và điều kiện bàn giao.

## Bước tiếp theo

Hoàn thành tải dependency, triển khai xác thực khuôn mặt, chạy test/build và thử trên Samsung Note 20 Ultra hoặc Android thật. Sau đó Bảo An cấu hình `WebAPI_TongNhatBaoAn`, database `AppChamCong_TongNhatBaoAn`, email/OTP thật, nối app của mình với dữ liệu thật rồi cung cấp base URL HTTPS cho các bạn sử dụng chung.

Không có cam kết server không bao giờ gián đoạn. Giai đoạn API sẽ cấu hình hosting chạy liên tục, healthcheck, log, sao lưu và phương án demo LAN.

## Tài liệu plugin

- https://pub.dev/packages/geolocator
- https://pub.dev/packages/mobile_scanner
- https://pub.dev/packages/share_plus
- https://pub.dev/packages/qr_flutter
- https://pub.dev/packages/cryptography

Khi `flutter pub get` thành công, commit `pubspec.lock` cùng source để cả nhóm dùng cùng phiên bản. Không commit `.env`, khóa ký, mật khẩu database hoặc SMTP.
