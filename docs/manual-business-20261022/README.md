# Bộ thay thế nghiệp vụ 1–8 — Chấm công thông minh

Được viết theo source thực tế trong repo ngày 22/10/2026. Đây là bộ file để **bạn dán thủ công**, chưa thay source đang chạy, chưa deploy Render, chưa chạy SQL lên Neon. Không có thay đổi layout, màu sắc hay cây widget.

Các file Dart trong thư mục tài liệu này được loại khỏi Dart analyzer vì chỉ là bộ thay thế, không phải thư viện độc lập. Project kiểm thử được lưu dưới tên `files/tool/BusinessChecks/Checks.csproj.template` để IDE không tự nạp khi chưa tích hợp. Khi áp dụng bộ file, chép file này thành `tool/BusinessChecks/Checks.csproj` ở gốc repo (bỏ đuôi `.template`). Không chép thư mục `obj/` hoặc `bin/`; đó là dữ liệu build được tạo lại trên máy. Sau khi chép vào đúng vị trí, các file sẽ được phân tích/build bình thường.

## 1–8: cách làm và file liên quan

| Mục | Cách làm | Code đầy đủ trong `files/` |
|---|---|---|
| 1. Múi giờ | Session PostgreSQL UTC; `timestamptz`; JSON DateTime luôn có `Z`; input thời điểm thiếu offset trả 400. Server tính ca theo `Asia/Ho_Chi_Minh`; Flutter parse rồi `toLocal()`. | `Services/BusinessRules.cs`, `Program.cs`, `lib/domain/models.dart` |
| 2. Luật chấm công | Vào sớm tối đa 60 phút; ra cách vào ít nhất 30 phút; GPS ≤50 m; không mock; chặn trùng; tự đóng ca quá hạn, không cộng giờ giả. Trạng thái là flags enum để giữ được cả đi trễ và về sớm. | `AttendanceService.cs`, `AttendanceController.cs`, `BusinessEntities.cs` |
| 3. Nghỉ/qua đêm | `BreakMinutes`, `EarlyLeaveGraceMinutes`; snapshot thông số vào Attendance. Giờ công là `max(0, floor((ra−vào)/phút)−nghỉ)/60`. Hỗ trợ cả ca bắt đầu gần 00:00 và vào sớm từ tối hôm trước. | `Entities.cs`, `Dtos.cs`, `BusinessRules.cs`, endpoint shifts trong `Controllers.cs` |
| 4. Thống kê | Điểm = 40×tỷ lệ đúng giờ + 30×tỷ lệ đủ giờ + 30×tỷ lệ checkout thật. Không dữ liệu/không giờ hợp lệ: 0 điểm, không “Xuất sắc”. Chỉ xếp hạng người >0 giờ. API cá nhân và công ty riêng. | `StatisticsService.cs`, `StatisticsController.cs`, `StatisticsRepository` |
| 5. Đăng ký | Public register chỉ nhận Name/Email/Username/Password, bỏ qua JSON role lạ; server gán employee và PendingApproval. Xác minh email xong vẫn phải chờ Admin duyệt. Mọi đường cấp/refresh JWT, face-login và kiểm tra JWT đều kiểm tra approval. | `Controllers.cs`, `ApprovalController.cs`, `FaceLoginController.cs`, `Program.cs` |
| 6. Đơn từ | `/mine` và `/pending-review` riêng; không tự duyệt; Manager chỉ duyệt Employee; đơn Manager/Admin do một Admin khác duyệt. Số ngày loại cuối tuần theo cấu hình; response có days/reviewedBy/reviewerName/reviewedAt. Khóa hàng nhân viên khi kiểm tra trùng đơn; xmin chống duyệt đè. | `RequestsController.cs`, `WorkRequest`/DTO, `RequestRepository` |
| 7. Gian lận | Mặc định văn phòng 100 m; QR HMAC với thời điểm và nonce, hạn 30–60 giây; khóa `(EmployeeId,TokenHash)` chống tái sử dụng; QR/face proof/attendance trong cùng transaction; từ chối mock flag. | `QrService` trong `BusinessRules.cs`, `QrRedemption`, `AttendanceService.cs` |
| 8. Dữ liệu | SQL sửa đúng tên; dọn theo danh sách username chính xác, giữ tài khoản có lịch sử ở trạng thái khóa. Nhân viên hoạt động = Employee/Manager đã xác minh, đã duyệt, chưa khóa; loại Admin. | `01-schema.sql`, `02-data-preview.sql`, `03-data-cleanup.sql`, `StatisticsService.cs` |

Đường dẫn backend trong bảng có tiền tố `WebAPI_TongNhatBaoAn/Services`, `Models`, `Controllers`, `Dtos` tương ứng. Xem `FULL_CODE.md` nếu muốn đọc và copy toàn bộ code trong một tài liệu.

## Áp dụng theo thứ tự

1. Giữ bản sao source/DB hiện tại. Chỉ dán vào đúng repo này: bộ code dùng tên entity/cột đang có của dự án, không phải mẫu độc lập.
2. Với mỗi file trong `files/`, chép **toàn bộ nội dung** vào đường dẫn tương ứng tính từ gốc repo. File mới thì tạo mới. Đặc biệt phải **thay** `Controllers/Controllers.cs`: bản thay thế đã tách Attendance/Requests ra file riêng, không được nối thêm vào file cũ vì sẽ trùng controller/route.
3. `Program.cs` và `AppDb.cs` bắt buộc đi cùng bộ này để đăng ký DI, BackgroundService, JSON UTC, approval gate và bảng/index. `FaceLoginController.cs` chỉ bổ sung approval gate, giữ nhận diện + OTP Brevo. Không đổi khóa Brevo/JWT/face encryption đang dùng.
4. Trộn các khóa trong `settings.example.json` vào appsettings hoặc cấu hình Render. Không ghi đè toàn bộ appsettings đang có.
5. Chọn **một** cách nâng schema: bật `RUN_MIGRATIONS=true` rồi deploy toàn bộ code/migrations, **hoặc** chạy `01-schema.sql` trong Neon SQL Editor trước khi đưa bản API mới lên. SQL có kiểm tra `__EFMigrationsHistory`; nếu sau đó vẫn bật RUN_MIGRATIONS, EF sẽ bỏ qua migration đã ghi nhận. Không chạy một bản ALTER thủ công khác rồi tự ghi history. Nếu DB đã tạo cột thủ công nhưng không có history tương ứng, cần đối chiếu schema trước khi dùng script này.
6. `01-schema.sql` bao gồm các migration từ đầu, bỏ qua migration đã có history, giữ các bảng face/departments. Migration mới: `20261022072020_AttendanceBusinessRules`. Các file migration cũ trong repo phải được giữ.
7. Mở `02-data-preview.sql`, kiểm tra tên/tài khoản/bán kính. Chạy `03-data-cleanup.sql` để xem kết quả; mặc định ROLLBACK. Khi đúng danh sách thì đổi dòng cuối thành COMMIT rồi chạy lại. Không xóa theo từ khóa `%test%` vì có thể trúng tài khoản thật.
8. Đăng xuất/đăng nhập lại, đồng bộ dữ liệu từ API, quét QR mới. QR cũ định dạng 3 phần không còn hợp lệ. API mới dùng `BAOAN:issuedUnixSeconds:nonce:hmac` (4 phần); scanner hiện tại vẫn đọc vì giữ tiền tố `BAOAN:`.

PowerShell tại gốc repo, sau khi dán file:

```powershell
dotnet build .\WebAPI_TongNhatBaoAn
dotnet run --project .\tool\BusinessChecks
dart analyze lib/domain/models.dart lib/data/api_repositories.dart
dart --packages=tool/BusinessChecks/empty_packages.json tool/BusinessChecks/check_models.dart
flutter run
```

Hai file test Dart được đặt dưới `tool/BusinessChecks`; import dùng đường dẫn trở về `lib`. Nếu máy bạn có Flutter SDK trên PATH thì dùng `dart` như trên. `dotnet build` không tự deploy; để Render cập nhật cần đẩy đúng source/migrations lên repo đã liên kết.

## Cấu hình Render

```text
Attendance__MaxEarlyCheckInMinutes=60
Attendance__MinSessionMinutes=30
Attendance__MaxAccuracyMeters=50
Attendance__QrLifetimeSeconds=60
Leave__ExcludedDays__0=Saturday
Leave__ExcludedDays__1=Sunday
Seed__AdminName=Tống Nhật Bảo An
```

Mốc ra tối thiểu phải ≥1; vào sớm 0–240 phút; sai số GPS tối đa không quá 50 m; QR 30–60 giây. Cấu hình không hợp lệ làm ứng dụng báo lỗi khởi động, tránh âm thầm chạy sai luật. Nếu muốn tính thứ Bảy là ngày phép, dùng JSON `ExcludedDays: ["Sunday"]` và xóa các biến môi trường mảng cũ trước khi thay. Không trộn hai mảng JSON/env khác nhau.

Nghỉ giữa ca mặc định 0 vì đề không ấn định mỗi ca nghỉ bao lâu. Đặt cho từng ca bằng API, ví dụ:

```http
PATCH /api/shifts/{shiftId}
Authorization: Bearer <admin-access-token>
Content-Type: application/json

{"name":"Ca ngày","startMinute":480,"endMinute":1020,"grace":5,"breakMinutes":60,"earlyLeaveGraceMinutes":5}
```

PATCH không gửi break/grace mới sẽ giữ cấu hình hiện có. `ShiftRepository.update(s, breakMinutes: 60, earlyLeaveGraceMinutes: 5)` dùng khi cần sửa hai thông số này. Không thêm ô nhập mới vì phạm vi không cho sửa widget.

## Quy ước cần biết

- `CheckIn`, `CheckOut`, `ScheduledStart`, `ScheduledEnd`, thời điểm duyệt và hết hạn đều là UTC `timestamptz`. PostgreSQL có thể hiển thị cùng một instant theo timezone session; điều đó không làm thay đổi dữ liệu. Ví dụ `05:50Z` chính là `12:50` tại Việt Nam, không được tự cộng 7 giờ vào DB.
- `From`, `To` là DateOnly, còn `WorkDate` là chuỗi ngày; không gọi `toUtc/toLocal` với các giá trị ngày thuần. Giữ quy ước cũ `WorkDate` = ngày kết thúc ca tại VN để không phá unique key lịch sử; thống kê dùng ngày bắt đầu ca snapshot.
- Auto-close muộn nhất **00:00 VN sau ngày kết thúc ca**, nhưng sớm hơn nếu cần mở cửa sổ vào ca kế tiếp; không bao giờ đóng trước giờ kết thúc ca. Ca 22:00 ngày 22 đến 06:00 ngày 23, vào sớm60, sẽ đóng lúc 21:00 ngày 23 để không chặn ca 22:00 tiếp theo. Ca ngày08:00–17:00 đóng lúc00:00 hôm sau. Worker chạy khoảng 30 giây/lần. Nếu Render ngủ, việc đóng diễn ra khi thức dậy hoặc khi gọi punch/list/stats, không thể hứa chạy đúng nửa đêm trong lúc process bị dừng.
- Khi tự đóng, CheckOut lưu mốc ScheduledEnd ước tính, `IsAutoClosed=true`, `AutoClosedAt` lưu lúc thực sự đóng; NetMinutes=0. Đây là hồ sơ “Quên check-out”, không phải bằng chứng người dùng đã ra và không được tính ca hoàn tất.
- Giờ công trừ toàn bộ BreakMinutes một lần cho mỗi checkout thật, không âm. Mô hình này chưa có giờ bắt đầu/kết thúc nghỉ để tính nghỉ giao nhau. Giờ vào sớm/làm sau ca vẫn nằm trong khoảng thực tế, chưa có quy tắc trả lương hoặc duyệt tăng ca riêng.
- Đi trễ/về sớm = số phút vượt dung sai, làm tròn lên; ví dụ 08:05:01 với dung sai 5 phút bị tính 1 phút trễ. Giờ công thực tế làm tròn xuống theo phút.
- Dung sai không tự cộng thêm giờ công. “Đủ giờ” trong công thức điểm dùng số phút thực tế sau nghỉ so với ExpectedMinutes, nên một ca trong dung sai vẫn có thể chưa đủ thời lượng chuẩn.
- Enum JSON: `DungGio`, `DiTre`, `VeSom`, `QuenCheckOut`, `BatThuong`; vừa trễ vừa sớm trả `"DiTre, VeSom"`. Lưu DB integer flags, không ép một tình trạng ghi đè tình trạng khác.
- Điểm chỉ xét bản ghi ca đã kết thúc hoặc đã có checkout, không phạt ca đang diễn ra. Mỗi tỷ lệ chia cho số bản ghi đủ điều kiện; không có giờ hợp lệ thì điểm 0. Đủ giờ yêu cầu NetMinutes ≥ ExpectedMinutes snapshot. ≥90 Xuất sắc, ≥75 Khá tốt, ≥50 Cần cải thiện, còn lại Chưa đạt. Đây là điểm **trên các ca có bản ghi**, chưa đo vắng mặt không có bản ghi vì hệ thống chưa có bảng lịch làm theo ngày.
- API công ty chỉ xét nhân viên hoạt động như định nghĩa ở trên. API cá nhân chỉ trả chính người đang đăng nhập, kể cả khi người đó là Admin. Không lấy trung bình điểm đã làm tròn của từng người để tính điểm công ty.
- Public signup cần OTP xác minh quyền sở hữu email, sau đó Admin duyệt; OTP đăng nhập là một challenge khác. Không thể dùng mã verify-email để lấy JWT qua verify-otp. Admin tạo tài khoản qua endpoint quản trị được quyền cấp Approved và chọn role; khác với tự đăng ký công khai.
- Chỉ một Admin thì người đó không thể tự duyệt đơn của mình. Cần Admin thứ hai được cấp hợp lệ; Manager không được duyệt thay Admin. Quyền được kiểm tra lại trên server, không dựa vào nút trên Flutter.
- Mock flag giúp chặn nguồn GPS bị hệ điều hành đánh dấu giả; client đã chỉnh sửa vẫn có thể khai gian cờ. Bộ này không tuyên bố chống giả GPS tuyệt đối hay có hardware attestation.

## Dữ liệu cũ: xử lý bảo toàn

Migration không thay CheckIn/CheckOut cũ. Vì bản ghi cũ không có snapshot giờ bắt đầu/nghỉ và có thể đã vào/ra cùng phút, migration đánh dấu tất cả lịch sử cũ `BatThuong`; thống kê tạm loại khỏi giờ hợp lệ. ScheduledStart tạm bằng CheckIn, ExpectedMinutes=0, chờ đối soát đúng ca. Đây là thay đổi có chủ ý, **không phải dữ liệu bị xóa**. Nếu bạn cần tính công lịch sử, phải đối soát từng ca và cập nhật snapshot/trạng thái bằng dữ liệu đã xác nhận; không chỉ xóa cờ BatThuong hàng loạt.

Các đơn cũ được backfill Days theo T2–T6 và ReviewerName nếu còn người duyệt; ReviewedAt giữ NULL vì trước đây không ghi thời điểm. Không dựng thời điểm duyệt bằng CreatedAt.

## Flutter: parse và hiển thị

Code này có sẵn trong model thay thế:

```dart
final localTime = parseApiInstant('2026-10-22T05:50:00Z');
final label = clock(localTime); // 12:50 nếu điện thoại đặt múi giờ Việt Nam
final requestBody = {'capturedAt': DateTime.now().toUtc().toIso8601String()};
// Date-only vẫn là ngày, không đổi múi giờ:
final leaveDay = DateTime.parse('2026-10-23');
```

Nếu điện thoại đặt múi giờ nước khác, `toLocal()` hiển thị giờ nước đó; luật ca vẫn theo Việt Nam ở server. Cache cũ lưu chuỗi thời điểm không có offset sẽ bị parser mới từ chối; xóa cache prototype cũ rồi tải lại API, không tự đoán múi giờ của chuỗi mơ hồ. Không xóa toàn bộ app nếu có mẫu sinh trắc chưa sao lưu cần giữ; dự án đang dùng API làm nguồn dữ liệu.

## API mới và đoạn nối dữ liệu — không sửa widget trong bộ chính

```text
GET  /api/registrations/pending                  Admin, trả user + version
POST /api/registrations/{id}/review              Admin, {approve,note,version}
GET  /api/requests/mine?status=pending           Mọi user, chỉ đơn của mình
GET  /api/requests/pending-review                Admin/Manager, chỉ đơn có quyền duyệt
POST /api/requests/{id}/review                   {approve,note,version} bắt buộc version
GET  /api/statistics/mine?from=2026-10-01&to=2026-10-31
GET  /api/statistics/company?from=2026-10-01&to=2026-10-31   Admin/Manager
```

`GET /api/requests` giữ route tương thích nhưng nay chỉ trả đơn của tôi. Vì thế **controller Flutter cũ gọi list() sẽ không tự có hàng chờ duyệt nữa**. Dùng hai nguồn riêng, không gộp rồi để client tự lọc quyền:

```dart
final myRequests = await controller.requestRepo.mine();
final reviewQueue = controller.isStaff
    ? await controller.requestRepo.pendingReview()
    : <WorkRequest>[];
// Chọn nguồn đúng mục đích khi truyền vào trang hiện có.
```

Duyệt tài khoản mới có thể test bằng Swagger hoặc service đã thêm:

```dart
final approvals = RegistrationApprovalRepository(controller.client);
final pending = await approvals.pending();
final item = pending.first as Map<String, dynamic>;
await approvals.review(
  id: item['user']['id'] as String,
  approve: true,
  note: 'Đã đối chiếu thông tin nhân viên',
  version: (item['version'] as num).toInt(),
);
```

Thống kê:

```dart
final repository = StatisticsRepository(controller.client);
final personal = await repository.mine(DateTime(2026,10,1), DateTime(2026,10,31));
final company = controller.isStaff
    ? await repository.company(DateTime(2026,10,1), DateTime(2026,10,31))
    : null;
final displayed = company == null
    ? personal
    : StatisticsSummary.fromJson(Map<String,dynamic>.from(company['summary']));
final score = displayed.score;        // Không dùng _attendanceScore cũ
final hours = displayed.netHours;
final rating = displayed.rating;
final sectionTitle = displayed.analysisTitle; // Phân tích tự động
final ranking = company?['ranking'] ?? [];     // Server đã loại 0 giờ
```

**Giới hạn phạm vi:** `lib/ui/stats_page.dart` hiện tự tính điểm, nhãn AI và xếp hạng trong getter/widget. Bộ chính chỉ sửa model/service đúng danh sách bạn cho phép, nên không tự thay các getter/nội dung Text trong file đó. Cần gắn các giá trị trên vào nơi đang hiển thị trước khi kết luận màn thống kê đã hết mâu thuẫn. Tương tự, bộ chính cung cấp service hàng chờ duyệt và approve signup, chưa thêm tab/nút duyệt mới. Đây không phải việc chỉ đổi backend rồi màn hình tự sử dụng API mới.

**Có code nối hoàn chỉnh để dán nếu cần:** `optional-integration/lib/ui/stats_page.dart` là toàn bộ file trang thống kê, tách khỏi `files/` vì nằm ngoài danh sách Flutter cho phép. File này giữ cây widget/bố cục/style, chỉ thay nguồn dữ liệu, vòng đời tải API, getter, nhãn và bucket tháng. Admin/Manager mặc định xem công ty, Employee xem cá nhân; cả hai endpoint vẫn dùng độc lập được. Chép thêm file này vào `lib/ui/stats_page.dart` sau bộ chính để màn hình dùng công thức mới. `OPTIONAL_STATS.patch` cho xem diff trước khi chép. Nó không thêm màn/nút duyệt tài khoản hay tab đơn từ. Bản này đã qua Dart analyzer, chưa test widget/điện thoại.

## Kiểm tra đã thực hiện và chưa thực hiện

- Backend bộ thay thế build thành công; lần kiểm tra cuối không có warning/error build.
- 61 kiểm tra C# qua: UTC/offset/Z, ca ngày/qua đêm/gần 00:00, giới hạn giờ, nghỉ, GPS/mock, QR hạn 30/60s/chữ ký, công thức điểm, ngày phép, quyền duyệt, mặc định pending, metadata khóa QR/xmin và SQL khóa chủ đơn.
- 15 kiểm tra Dart qua: UTC/offset, reject thiếu timezone, giờ net, cache UTC, auto-close/abnormal không giờ, approval và metadata duyệt.
- `dart analyze` hai file Flutter thay thế: không issue ở lần kiểm tra đã chạy; chạy lại sau khi dán.
- SQL được sinh từ EF/Npgsql; chưa thực thi lên PostgreSQL/Neon. Các test metadata/SQL generation không thay cho test đồng thời thật trên DB.
- Chưa gửi OTP/email thật, chưa gọi API Render, chưa test camera/GPS trên điện thoại, chưa build APK cho bộ thay thế này.
- Xem `TEST_MANUAL.md` để test sau khi áp dụng lên môi trường thử nghiệm.
