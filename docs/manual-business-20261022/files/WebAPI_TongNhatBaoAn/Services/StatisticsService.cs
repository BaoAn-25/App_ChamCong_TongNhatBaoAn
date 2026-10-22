using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Models;
namespace WebAPI_TongNhatBaoAn.Services;

public record AttendanceSummary(int EligibleShifts, int OnTimeShifts, int AdequateShifts, int ActualCheckouts,
    double NetHours, double Score, string Rating, string AnalysisTitle = "Phân tích tự động")
{
    public int LateShifts { get; init; }
    public int TotalLateMinutes { get; init; }
}
public record RankingRow(Guid EmployeeId, string Name, AttendanceSummary Summary);
public static class AttendanceScoring
{
    public static AttendanceSummary Calculate(IEnumerable<Attendance> source, DateTime now)
    {
        var rows = source.Where(a => a.ScheduledEnd <= now || a.CheckOut != null).ToList();
        bool Actual(Attendance a) => a.CheckOut != null && !a.IsAutoClosed && a.CheckOut > a.CheckIn &&
            !a.Status.HasFlag(AttendanceStatus.BatThuong);
        var onTime = rows.Count(a => a.LateMinutes == 0 && !a.Status.HasFlag(AttendanceStatus.BatThuong));
        var adequate = rows.Count(a => Actual(a) && a.NetMinutes > 0 && a.ExpectedMinutes > 0 && a.NetMinutes >= a.ExpectedMinutes);
        var checkout = rows.Count(Actual);
        var minutes = rows.Where(Actual).Sum(a => (long)Math.Max(0,a.NetMinutes));
        var score = rows.Count == 0 || minutes == 0 ? 0 : Math.Round((40d * onTime + 30d * adequate + 30d * checkout) / rows.Count,1);
        var rating = minutes == 0 ? "Chưa có giờ công hợp lệ" : score >= 90 ? "Xuất sắc" : score >= 75 ? "Khá tốt" : score >= 50 ? "Cần cải thiện" : "Chưa đạt";
        return new(rows.Count,onTime,adequate,checkout,minutes / 60d,score,rating) {
            LateShifts = rows.Count(a => a.LateMinutes > 0),
            TotalLateMinutes = rows.Sum(a => Math.Max(0,a.LateMinutes))
        };
    }
}
public sealed class StatisticsService(AppDb db, AttendanceService attendance, TimeProvider clock)
{
    private async Task<List<Attendance>> Load(DateOnly from, DateOnly to, Guid? employee)
    {
        if (from.Year < 1970 || to.Year > 9998 || to < from || to.DayNumber - from.DayNumber > 365)
            throw new BusinessException("Chọn đủ ngày bắt đầu/kết thúc, khoảng thống kê tối đa 366 ngày.");
        await attendance.CloseOverdueAsync();
        var start = TimeVn.ToUtc(from.ToDateTime(TimeOnly.MinValue));
        var end = TimeVn.ToUtc(to.AddDays(1).ToDateTime(TimeOnly.MinValue));
        var q = db.Attendance.AsNoTracking().Where(a => a.ScheduledStart >= start && a.ScheduledStart < end);
        if (employee != null) q = q.Where(a => a.EmployeeId == employee);
        return await q.ToListAsync();
    }
    public async Task<AttendanceSummary> Personal(Guid id,DateOnly from,DateOnly to) =>
        AttendanceScoring.Calculate(await Load(from,to,id), clock.GetUtcNow().UtcDateTime);
    public async Task<object> Company(DateOnly from, DateOnly to)
    {
        var employees = await db.Employees.AsNoTracking().Where(e => e.Active && e.EmailVerified && (e.Role == Roles.Employee || e.Role == Roles.Manager) && e.ApprovalStatus == ApprovalStatus.Approved)
            .Select(e => new { e.Id, e.Name }).ToListAsync();
        var ids = employees.Select(e => e.Id).ToHashSet();
        var rows = (await Load(from,to,null)).Where(a => ids.Contains(a.EmployeeId)).ToList();
        var now = clock.GetUtcNow().UtcDateTime;
        var ranking = employees.Select(e => new RankingRow(e.Id,e.Name,AttendanceScoring.Calculate(rows.Where(a => a.EmployeeId == e.Id),now)))
            .Where(r => r.Summary.NetHours > 0).OrderByDescending(r => r.Summary.Score).ThenByDescending(r => r.Summary.NetHours).ThenBy(r => r.EmployeeId).ToList();
        return new { activeEmployees = employees.Count, summary = AttendanceScoring.Calculate(rows,now), ranking };
    }
}
