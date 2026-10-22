using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;
namespace WebAPI_TongNhatBaoAn.Services;

public sealed class AttendanceService(AppDb db, QrService qr, FaceAttendancePolicy face,
    IOptions<AttendanceOptions> options, IOptions<LeaveOptions> leaveOptions, TimeProvider clock)
{
    public async Task CloseOverdueAsync(CancellationToken ct = default)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        // Atomic predicate also prevents a racing checkout from being overwritten.
        await db.Attendance.Where(a => a.CheckOut == null && a.AutoCloseAt <= now)
            .ExecuteUpdateAsync(s => s.SetProperty(a => a.CheckOut, a => (DateTime?)a.ScheduledEnd)
                .SetProperty(a => a.IsAutoClosed, true).SetProperty(a => a.AutoClosedAt, now)
                .SetProperty(a => a.NetMinutes, 0)
                .SetProperty(a => a.Status, a => a.Status | AttendanceStatus.QuenCheckOut), ct);
    }

    private void Validate(PunchRequest r, Office office, DateTime now)
    {
        if (!office.Configured) throw new BusinessException("Admin chưa cấu hình văn phòng.", 409);
        if (string.IsNullOrWhiteSpace(r.IdempotencyKey) || r.IdempotencyKey.Length > 100)
            throw new BusinessException("Thiếu mã yêu cầu hoặc mã quá dài.");
        if (!qr.IsValid(office.QrSecret, r.Qr, now)) throw new BusinessException("QR sai hoặc hết hạn. Hãy quét mã mới.");
        BusinessRules.ValidateLocation(r,office,now,options.Value.MaxAccuracyMeters);
    }

    public async Task<AttendanceDto> PunchAsync(Guid uid, PunchRequest r, bool checkIn)
    {
        // Catch-up also runs when a sleeping Render instance wakes up.
        await CloseOverdueAsync();
        try
        {
            return await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync();
                var employee = await db.Employees.SingleOrDefaultAsync(e => e.Id == uid);
                if (employee == null || !BusinessRules.CanUse(employee)) throw new BusinessException("Tài khoản chưa được duyệt hoặc bị khóa.", 403);
                var existing = checkIn
                    ? await db.Attendance.SingleOrDefaultAsync(a => a.EmployeeId == uid && a.IdempotencyKey == r.IdempotencyKey)
                    : await db.Attendance.SingleOrDefaultAsync(a => a.EmployeeId == uid && a.CheckOutIdempotencyKey == r.IdempotencyKey);
                // Network retry is not another redemption. Return exactly the successful operation.
                if (existing != null) { await tx.CommitAsync(); return BusinessRules.Dto(existing, employee.Name); }
                var now = clock.GetUtcNow().UtcDateTime;
                var office = await db.Offices.FindAsync(1) ?? new Office();
                Validate(r, office, now);
                var hash = TokenService.Hash(r.Qr);
                if (await db.QrRedemptions.AnyAsync(q => q.EmployeeId == uid && q.TokenHash == hash))
                    throw new BusinessException("Bạn đã dùng QR này. Hãy quét QR mới.", 409);
                Attendance row;
                if (checkIn)
                {
                    if (await db.Attendance.AnyAsync(a => a.EmployeeId == uid && a.CheckOut == null))
                        throw new BusinessException("Bạn còn ca chưa chấm công ra.", 409);
                    var shift = employee.ShiftId == null ? null : await db.Shifts.FindAsync(employee.ShiftId);
                    if (shift == null) throw new BusinessException("Bạn chưa được phân ca.", 409);
                    var window = BusinessRules.Window(shift, now, options.Value.MaxEarlyCheckInMinutes);
                    // Keep the existing database convention: WorkDate is the VN date when the shift ends.
                    var workDate = TimeVn.DayKey(TimeVn.ToLocal(window.End));
                    if (await db.Attendance.AnyAsync(a => a.EmployeeId == uid && a.WorkDate == workDate))
                        throw new BusinessException("Đã có bản ghi của ca ngày này.", 409);
                    var day = DateOnly.FromDateTime(TimeVn.ToLocal(window.Start));
                    if (!leaveOptions.Value.ExcludedDays.Contains(day.DayOfWeek) &&
                        await db.WorkRequests.AnyAsync(w => w.EmployeeId == uid && w.Type == RequestTypes.Leave &&
                        w.Status == RequestStatus.Approved && w.From <= day && w.To >= day))
                        throw new BusinessException("Ngày bắt đầu ca đã được duyệt nghỉ phép.", 409);
                    var late = BusinessRules.Late(now, window.Start, shift.Grace);
                    row = new Attendance {
                        EmployeeId = uid, ShiftName = shift.Name, WorkDate = workDate, CheckIn = now,
                        ScheduledStart = window.Start, ScheduledEnd = window.End, AutoCloseAt = window.AutoClose,
                        BreakMinutes = shift.BreakMinutes, EarlyLeaveGraceMinutes = shift.EarlyLeaveGraceMinutes,
                        ExpectedMinutes = BusinessRules.NetMinutes(window.Start, window.End, shift.BreakMinutes),
                        LateMinutes = late, Status = late > 0 ? AttendanceStatus.DiTre : AttendanceStatus.DungGio,
                        Latitude = r.Latitude, Longitude = r.Longitude, Accuracy = r.Accuracy, IdempotencyKey = r.IdempotencyKey
                    };
                    db.Attendance.Add(row);
                }
                else
                {
                    row = await db.Attendance.SingleOrDefaultAsync(a => a.EmployeeId == uid && a.CheckOut == null)
                        ?? throw new BusinessException("Bạn chưa chấm công vào hoặc ca đã tự đóng.", 409);
                    BusinessRules.EnsureCheckoutAllowed(row,now,options.Value.MinSessionMinutes);
                    row.CheckOut = now;
                    row.OutLatitude = r.Latitude; row.OutLongitude = r.Longitude;
                    row.CheckOutIdempotencyKey = r.IdempotencyKey;
                    row.EarlyLeaveMinutes = BusinessRules.Early(now, row.ScheduledEnd, row.EarlyLeaveGraceMinutes);
                    row.NetMinutes = BusinessRules.NetMinutes(row.CheckIn, now, row.BreakMinutes);
                    if (row.EarlyLeaveMinutes > 0) row.Status |= AttendanceStatus.VeSom;
                }
                var faceError = await face.Consume(uid, r.FaceProof, checkIn ? "check-in" : "check-out");
                if (faceError != null) throw new BusinessException(faceError, 403);
                db.QrRedemptions.Add(new QrRedemption { EmployeeId = uid, TokenHash = hash, RedeemedAt = now });
                await db.SaveChangesAsync();
                await tx.CommitAsync();
                return BusinessRules.Dto(row, employee.Name);
            });
        }
        catch (DbUpdateConcurrencyException) { throw new BusinessException("Ca vừa được xử lý. Hãy tải lại.", 409); }
        catch (DbUpdateException ex) when (ex.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            db.ChangeTracker.Clear();
            var done = checkIn
                ? await db.Attendance.AsNoTracking().SingleOrDefaultAsync(a => a.EmployeeId == uid && a.IdempotencyKey == r.IdempotencyKey)
                : await db.Attendance.AsNoTracking().SingleOrDefaultAsync(a => a.EmployeeId == uid && a.CheckOutIdempotencyKey == r.IdempotencyKey);
            if (done != null) return BusinessRules.Dto(done, await db.Employees.Where(e => e.Id == uid).Select(e => e.Name).SingleAsync());
            throw new BusinessException("Yêu cầu trùng lặp hoặc QR đã dùng. Hãy tải lại.", 409);
        }
    }
}

public sealed class AttendanceClosingWorker(IServiceScopeFactory scopes, ILogger<AttendanceClosingWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                await scope.ServiceProvider.GetRequiredService<AttendanceService>().CloseOverdueAsync(ct);
                var cutoff = DateTime.UtcNow.AddDays(-2);
                await db.QrRedemptions.Where(q => q.RedeemedAt < cutoff).ExecuteDeleteAsync(ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Auto-close attendance failed; will retry."); }
            try { await Task.Delay(TimeSpan.FromSeconds(30), ct); }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
        }
    }
}
