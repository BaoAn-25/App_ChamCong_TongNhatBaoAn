> Cập nhật mới: camera trước hiển thị trực tiếp bên trong Flutter bằng package `camera`. Đã thêm đăng nhập tên tài khoản → camera đối sánh → OTP email → cấp phiên. Xem phần “Camera trực tiếp và đăng nhập” ở cuối tài liệu. Các kiểm tra mô hình/backend ở dưới vẫn dùng lại cho luồng này.

# Xác thực khuôn mặt khi chấm vào và ra ca

## Kết quả kiểm tra phần Antigravity

- `local_auth` chỉ gọi sinh trắc do điện thoại cung cấp. Không thể coi việc có nút Face ID / Vân tay là đã đối sánh khuôn mặt nhân viên.
- QR và chia sẻ vị trí đã có code. Phần tra địa chỉ và mở Maps được bổ sung nhưng trước đây có đường xử lý đóng nhầm trang khi lỗi tra địa chỉ. Đã thay bằng trạng thái đang tải, lỗi tại chỗ và timeout tra địa chỉ.
- Ảnh lỗi build cũ chỉ có dòng tổng kết `assembleDebug failed`; không chứa exception gốc. Phân tích Dart hiện không có vấn đề. Có APK cũ từ 13:17 ngày 22/10 trên máy, không dùng APK cũ làm bằng chứng cho bản sửa này.
- Chưa có đăng ký mẫu và đối sánh mặt theo nhân viên trong mã cũ. Bản này đã thêm đối sánh SFace trên backend, dùng cho **cả check-in và check-out**.

## Luồng mới

1. Đăng nhập bằng mật khẩu + OTP như trước.
2. Vào Tài khoản → Khuôn mặt khi chấm công → Đăng ký khuôn mặt.
3. Đồng ý xử lý mẫu; hệ thống gửi OTP email. Chụp 2 ảnh mới bằng camera, nhìn thẳng, đủ sáng. Nhập OTP quản lý mẫu.
4. Backend xác nhận OTP thuộc chính tài khoản; phát hiện đúng một khuôn mặt; kiểm tra chất lượng; đối sánh hai ảnh cùng người; lưu một vector SFace 128 chiều đã mã hóa AES-GCM trong PostgreSQL.
5. Khi chấm công: lấy GPS + QR → chụp mặt → backend đối sánh với mẫu tài khoản → nhận bằng chứng ngẫu nhiên có hạn 90 giây → cập nhật GPS mới → gửi yêu cầu chấm công kèm bằng chứng.
6. Bằng chứng bị ràng buộc với nhân viên và mục đích `check-in` hoặc `check-out`, chỉ tiêu thụ được một lần bằng UPDATE có điều kiện trên DB.
7. Backend vẫn kiểm tra GPS, thời gian, QR, ca làm, nghỉ phép, tài khoản hoạt động. Mặt khớp không thay các điều kiện đó.

Tài khoản **chưa đăng ký mặt** tiếp tục GPS + QR như cũ. Sau khi đăng ký, API chấm công bắt buộc nhận bằng chứng mặt hợp lệ; sửa Flutter để bỏ chụp ảnh cũng không bỏ được điều kiện server. Xóa/đăng ký lại mẫu cần OTP email mới và chỉ tác động tài khoản đang đăng nhập.

## Phạm vi và giới hạn

- Đây là face verification 1:1, không phải chỉ phát hiện có khuôn mặt, không phải vân tay hệ điều hành và không phải so ảnh bằng chuỗi hoặc hash ảnh.
- Ảnh được chọn từ **camera**, không có chọn từ thư viện. Camera trước được ưu tiên; một số ứng dụng camera Android vẫn có thể cho đổi camera.
- Chưa có mô hình chống ảnh chụp/video phát lại (liveness / presentation attack detection). Vì vậy không tuyên bố chống chấm công hộ tuyệt đối; không dùng như giải pháp bảo mật sinh trắc hoàn chỉnh.
- Server không lưu ảnh gốc, chỉ xử lý trong RAM. Trên Android, app cố gắng xóa tệp ảnh tạm do camera trả về ngay sau khi đọc; nếu hệ điều hành không cho xóa, cache vẫn theo vòng đời của thiết bị.
- Điểm cosine dùng ngưỡng 0.45. Ngưỡng này là cấu hình cố định thận trọng cho demo, chưa được hiệu chỉnh trên dữ liệu thực tế của lớp; vẫn có thể từ chối nhầm/nhận nhầm. Cần test nhiều người, ánh sáng, kính, góc nhìn.
- Đã có đăng nhập bằng khuôn mặt SFace + OTP. Backend chỉ so mẫu của tên tài khoản đã nhập (1:1), không dò danh tính trong toàn bộ nhân viên. Vân tay và QR vẫn cùng mục e. Việc công nhận mục a cần demo đúng/sai người trên thiết bị thật.

## Triển khai Render

Dockerfile đã thêm Python worker OpenCV chạy **nội bộ 127.0.0.1:5051 trong cùng container** với Web API C#. Không cần tài khoản dịch vụ nhận diện khuôn mặt hoặc API trả phí riêng.

1. Commit/push bản sửa có cả Dockerfile, `face_worker`, migration và mã Dart. Không chỉ copy `Controllers.cs` hoặc gửi APK cũ.
2. Render dùng Dockerfile trong `WebAPI_TongNhatBaoAn` như cấu hình cũ. Giữ `RUN_MIGRATIONS=true` ở server chính để tạo `FaceProfiles` và `FaceGrants`. Không xóa DB hoặc sửa migration cũ.
3. Thêm `Face__EncryptionKey`: một chuỗi bí mật ngẫu nhiên dài ít nhất 32 ký tự, chỉ lưu trên server. Nên đặt **trước lần đăng ký mẫu đầu tiên** và giữ ổn định qua các lần deploy. Nếu không đặt, code dùng khóa dẫn xuất từ `Jwt__Key`; thay khóa sẽ khiến mẫu cũ không giải mã được và phải đăng ký lại bằng OTP.
4. Giữ cấu hình gửi OTP email đang dùng; mẫu khuôn mặt không bỏ qua OTP ở bước quản lý mẫu.
5. Docker build cài thư viện và tải YuNet + SFace chính thức (~40MB), kiểm tra SHA-256 và lấy LICENSE đi kèm. Build lần đầu lâu hơn bản API cũ. Nếu tải model thất bại thì build thất bại, không dùng mẫu giả.
6. Chờ Render báo Live, chạy lại Flutter bằng `flutter pub get` rồi `flutter run`. Không cần thêm package Flutter ngoài `image_picker` đã có trong dự án.

Nếu worker gặp lỗi, API chính vẫn chạy; endpoint khuôn mặt trả 503 và không cho tài khoản đã bật mặt bỏ qua đối sánh. Render Free dùng chung RAM/CPU cho .NET và OpenCV, cần theo dõi bộ nhớ và độ trễ trên instance thật; chưa đo mức sử dụng tại Render.

## Chạy local để kiểm tra

Terminal 1:

```powershell
python -m pip install -r WebAPI_TongNhatBaoAn/face_worker/requirements.txt
python WebAPI_TongNhatBaoAn/face_worker/download_models.py
python WebAPI_TongNhatBaoAn/face_worker/worker.py
```

Terminal 2: cấu hình DB/JWT/SMTP API như dự án hiện tại và chạy `dotnet run --project WebAPI_TongNhatBaoAn`. Worker và API cần chạy cùng máy vì kết nối loopback. Flutter trên điện thoại vẫn gọi URL Web API có thể truy cập được.

## Test thực tế trên điện thoại

| Thử | Kết quả yêu cầu |
|---|---|
| Đăng ký 2 ảnh cùng người và OTP đúng | Báo đã đăng ký; đăng nhập máy khác vẫn có mẫu vì lưu server. |
| OTP sai/hết hạn/OTP của tài khoản khác | Không đổi hoặc tạo mẫu. OTP đăng nhập không dùng cho quản lý mẫu. |
| Hai ảnh khác người | Không lưu mẫu; xin OTP mới rồi chụp lại. |
| Không mặt, nhiều mặt, quá xa, ảnh mờ/tối | Báo nguyên nhân để chụp lại. |
| Đúng mặt + GPS/QR/ca hợp lệ | Chấm vào được; tiếp tục chụp mặt khi chấm ra. |
| Người khác cầm điện thoại đang đăng nhập tài khoản mình | Không khớp mặt → không có bằng chứng → không ghi công. |
| Đúng mặt nhưng QR sai/ngoài bán kính/chưa phân ca/nghỉ phép | Không ghi công; sửa điều kiện rồi chụp lại nếu bằng chứng đã hết hạn. |
| Dùng lại bằng chứng/đổi check-in thành check-out/đổi tài khoản | Backend từ chối, không tạo bản ghi mới. |
| Hủy camera hoặc từ chối quyền camera | Không chấm công, vẫn có thể quay lại màn trước. |
| Tắt worker | Báo 503; tài khoản có mẫu không tự bỏ qua xác thực. |
| Xóa mẫu bằng OTP đúng | Chuyển lại GPS + QR; không xóa tài khoản/bảng công. |
| GPS có tọa độ nhưng không tra được địa chỉ | Tọa độ vẫn hiện; tra địa chỉ không được chặn chấm công. |

Khi ảnh không đạt hoặc worker lỗi sau khi đã nhập OTP đăng ký, OTP đã được tiêu thụ để bảo đảm dùng một lần; cần xin OTP mới. Mẫu cũ vẫn giữ nếu việc đăng ký lại chưa thành công.

## Kiểm chứng đã thực hiện

- 9 kiểm tra với OpenCV/SFace thật trên ảnh mẫu công khai chính thức (cùng người, lật ảnh, khác người, nhiều/không mặt, ảnh hỏng/quá lớn/độ phân giải thấp). Ảnh người thứ hai có độ phân giải thấp bị chặn bởi bộ lọc chất lượng; kiểm tra khác người còn đối chiếu riêng vector thực từ SFace.
- 11 kiểm tra .NET: cosine, vector rỗng/sai kích thước/NaN, mã hóa/giải mã, nonce khác nhau, chống sửa mẫu, xử lý kết quả worker và lỗi dịch vụ.
- Build backend thành công; phân tích Dart sạch.
- Chưa chạy Docker trên Render, migration trên DB thật, chấm công với khuôn mặt người dùng, chống giả mạo hoặc build/install APK mới trên điện thoại. Không coi các mục này là đã kiểm chứng.

Chạy lại:

```powershell
python tool/check_face_worker.py
dotnet run --project tool/FaceChecks
dotnet build WebAPI_TongNhatBaoAn
flutter analyze
```

Nguồn mô hình/tài liệu: https://github.com/opencv/opencv_zoo và https://docs.opencv.org/4.12.0/d0/dd4/tutorial_dnn_face.html

## Camera trực tiếp và đăng nhập

- Mở video camera trước **ngay trong app**, có khung hướng dẫn và nút **Chụp & tiếp tục**. Không mở app camera ngoài hoặc thư viện ảnh cho bước xác thực mặt.
- Video là preview để căn khuôn mặt. Chỉ ảnh mới chụp khi bấm nút được gửi đến backend, không truyền video liên tục. Khung oval không phải kết quả phát hiện khuôn mặt.
- Khi server từ chối (sai người, tối, mờ, nhiều mặt), giữ màn camera cùng thông báo để chụp lại. Khi đồng ý, đóng camera và tiếp tục luồng gọi.
- Camera không thu âm. Giải phóng khi rời trang hoặc đưa app xuống nền, mở lại khi quay về. Nếu không có camera trước/camera bị chiếm/từ chối quyền, báo lỗi và có nút thử lại.
- Hủy camera không ghi công hoặc tạo phiên đăng nhập. Nếu yêu cầu nhận diện đã gửi trước lúc hủy, server có thể đã gửi OTP hoặc tạo proof; app không dùng kết quả đó, proof tự hết hạn.

### Bật và test đăng nhập bằng camera

1. Deploy bản backend mới có **cả AddFaceIdentity và EnableFaceLogin**, worker, Dockerfile; giữ `RUN_MIGRATIONS=true` ở server chính.
2. Chạy `flutter pub get` và chạy lại hoàn toàn app bằng `flutter run` (không chỉ hot reload vì có thêm plugin `camera`).
3. Đăng nhập mật khẩu + OTP một lần → Tài khoản → Khuôn mặt của bạn.
4. Bật **Cho phép đăng nhập bằng camera + OTP**, bấm Đăng ký/Đăng ký lại mẫu, chụp 2 ảnh với camera trực tiếp, xác nhận OTP. Lựa chọn switch chỉ được lưu cùng thao tác đăng ký mẫu thành công.
5. Mẫu cũ được migration đặt `AllowLogin=false`, không tự bật quyền dùng mẫu cho mục đích mới. Muốn bật phải đăng ký lại bằng OTP.
6. Đăng xuất → nhập tên đăng nhập → **Camera khuôn mặt + OTP** → căn mặt, bấm Chụp & tiếp tục → khớp thì nhận OTP email → nhập OTP để vào trang theo vai trò.
7. Sai mặt/tài khoản khóa/chưa xác minh/chưa có mẫu/chưa cho phép login: không tạo phiên. Face khớp cũng chưa cấp JWT; cần OTP đúng, còn hạn và chưa dùng.
8. Gửi lại OTP trong luồng mặt sẽ yêu cầu xác thực camera lại; không dùng ô mật khẩu đang trống.
9. Test chấm vào/ra như cũ: QR + GPS → mở camera trực tiếp → khớp mặt → ghi nhận trên server. Hủy hoặc sai người không ghi công.

Endpoint mới `POST /api/auth/face-login` nhận `username`, `image` và chỉ trả `challengeId`; dùng lại `POST /api/auth/verify-otp` để lấy token. Mật khẩu + OTP và sinh trắc của điện thoại vẫn là các nút riêng biệt.

### Kiểm tra bổ sung

- Test camera lifecycle: mở → bấm Home → quay lại → vẫn mở camera; hủy khi đang tải ảnh không pop nhầm trang hoặc tiếp tục đăng nhập.
- Test từ chối quyền và thiết bị không có camera trước; vẫn quay về đăng nhập mật khẩu được.
- Test sai mặt rồi chụp lại đúng ngay trên cùng trang camera.
- Test bấm liên tục: chỉ có một ảnh đang xử lý tại một thời điểm.
- Kiểm tra `test/face_contract_test.dart`: consent, bật/tắt login, proof vào/ra, face-login chỉ tạo OTP challenge và không lưu token khi chưa xác thực OTP.
- Chưa đo trực tiếp camera Samsung, chưa khẳng định build APK/Render đạt cho bản mới. Kiểm tra tĩnh và build backend không thay thế test trên máy thật.


Bản camera trực tiếp đã qua build backend và kiểm tra model/migration không còn thay đổi chưa có migration; các file Dart và test phân tích tĩnh không có lỗi. Đã bổ sung `test/face_camera_test.dart` mô phỏng camera: sai người/thử lại, hủy khi xác thực đang chạy, từ chối quyền và đưa app xuống nền/quay lại. Chưa chạy được các widget/contract tests này trong môi trường công cụ do quyền ghi tệp telemetry của hook `objective_c`; cần chạy trên terminal của bạn:

```powershell
flutter test test/face_camera_test.dart test/face_contract_test.dart
```

Không coi test giả lập platform là đã xác nhận camera, ánh sáng, hiệu năng hoặc chất lượng nhận diện trên điện thoại thật.
