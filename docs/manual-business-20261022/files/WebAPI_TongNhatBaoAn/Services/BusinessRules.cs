using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;

namespace WebAPI_TongNhatBaoAn.Services;

public sealed class AttendanceOptions
{
    public int MaxEarlyCheckInMinutes { get; set; } = 60;
    public int MinSessionMinutes { get; set; } = 30;
    public double MaxAccuracyMeters { get; set; } = 50;
    public int QrLifetimeSeconds { get; set; } = 60;
}
public sealed class LeaveOptions
{
    public DayOfWeek[] ExcludedDays { get; set; } = [DayOfWeek.Saturday, DayOfWeek.Sunday];
}
public sealed class BusinessException(string message, int status = 400) : Exception(message)
{
    public int Status { get; } = status;
}
public static class TimeVn
{
    private static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Ho_Chi_Minh");
    public static DateTime Utc(DateTime value) => value.Kind == DateTimeKind.Local
        ? value.ToUniversalTime() : DateTime.SpecifyKind(value, DateTimeKind.Utc);
    public static DateTime ToLocal(DateTime utc) => TimeZoneInfo.ConvertTimeFromUtc(Utc(utc), Zone);
    public static DateTime ToUtc(DateTime local) => TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(local, DateTimeKind.Unspecified), Zone);
    public static string DayKey(DateTime local) => local.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
public sealed class UtcDateTimeConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        var text = reader.GetString() ?? "";
        if (!System.Text.RegularExpressions.Regex.IsMatch(text, @"(Z|[+-]\d{2}:\d{2})$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)
            || !DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out var value))
            throw new JsonException("Thời điểm phải có Z hoặc độ lệch múi giờ; ví dụ 2026-10-22T05:50:00Z.");
        return value.UtcDateTime;
    }
    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options) =>
        writer.WriteStringValue(TimeVn.Utc(value).ToString("O", CultureInfo.InvariantCulture));
}
public static class BusinessRules
{
    public static void EnsureCheckoutAllowed(Attendance row, DateTime now, int minimumMinutes)
    {
        if (now >= row.AutoCloseAt) throw new BusinessException("Ca đã quá hạn chấm ra; hãy gửi đơn giải trình.",409);
        if ((now - row.CheckIn).TotalMinutes < minimumMinutes)
            throw new BusinessException($"Phải cách lần vào ít nhất {minimumMinutes} phút.",409);
    }
    public static void ValidateLocation(PunchRequest r, Office office, DateTime now, double maxAccuracy)
    {
        if (r.IsMocked) throw new BusinessException("Không chấp nhận vị trí giả lập.",403);
        if (!double.IsFinite(r.Accuracy) || r.Accuracy < 0 || r.Accuracy > maxAccuracy ||
            !double.IsFinite(r.Latitude) || Math.Abs(r.Latitude) > 90 ||
            !double.IsFinite(r.Longitude) || Math.Abs(r.Longitude) > 180 ||
            (now-r.CapturedAt).TotalSeconds > 60 || r.CapturedAt > now.AddSeconds(5))
            throw new BusinessException($"GPS không hợp lệ hoặc sai số vượt {maxAccuracy} m.");
        if (GeoService.DistanceMeters(r.Latitude,r.Longitude,office.Latitude!.Value,office.Longitude!.Value) > office.Radius)
            throw new BusinessException("Vị trí nằm ngoài bán kính văn phòng.");
    }
    public static bool CanUse(Employee e) => e.Active && e.EmailVerified && e.ApprovalStatus == ApprovalStatus.Approved;
    public static (DateTime Start, DateTime End, DateTime AutoClose) Window(Shift shift, DateTime utc, int earlyMinutes)
    {
        var local = TimeVn.ToLocal(utc);
        var duration = (shift.EndMinute - shift.StartMinute + 1440) % 1440;
        if (duration == 0) throw new BusinessException("Giờ bắt đầu và kết thúc ca phải khác nhau.");
        var start = local.Date.AddMinutes(shift.StartMinute);
        // Find a window containing now, including check-in before a 00:30 shift on the previous date.
        var candidates = new[] { start.AddDays(-1), start, start.AddDays(1) };
        start = candidates.Where(x => local >= x.AddMinutes(-earlyMinutes) && local < x.AddMinutes(duration))
            .OrderBy(x => Math.Abs((local - x).TotalMinutes)).FirstOrDefault();
        if (start == default) throw new BusinessException($"Chỉ được vào trước giờ ca tối đa {earlyMinutes} phút và trước khi ca kết thúc.", 409);
        var end = start.AddMinutes(duration);
        return (TimeVn.ToUtc(start), TimeVn.ToUtc(end), TimeVn.ToUtc(end.Date.AddDays(1)));
    }
    public static int Late(DateTime now, DateTime start, int grace) => Math.Max(0, (int)Math.Ceiling((now - start).TotalMinutes - grace));
    public static int Early(DateTime now, DateTime end, int grace) => Math.Max(0, (int)Math.Ceiling((end - now).TotalMinutes - grace));
    public static int NetMinutes(DateTime start, DateTime end, int rest) => Math.Max(0, (int)Math.Floor((end - start).TotalMinutes) - rest);
    public static int LeaveDays(DateOnly from, DateOnly to, LeaveOptions options)
    {
        if (from.Year < 1970 || to.Year > 9998 || to < from || to.DayNumber - from.DayNumber > 365)
            throw new BusinessException("Khoảng ngày phải hợp lệ, có đủ ngày bắt đầu/kết thúc và không quá 366 ngày.");
        return Enumerable.Range(0, to.DayNumber - from.DayNumber + 1)
            .Count(i => !options.ExcludedDays.Contains(from.AddDays(i).DayOfWeek));
    }
    public static bool CanReview(Guid reviewer, string reviewerRole, Guid owner, string ownerRole) =>
        reviewer != owner && (reviewerRole == Roles.Admin || reviewerRole == Roles.Manager && ownerRole == Roles.Employee);
    public static AttendanceDto Dto(Attendance a, string? name) => new(a.Id, a.EmployeeId, name, a.ShiftName,
        a.WorkDate, a.CheckIn, a.ScheduledEnd, a.LateMinutes, a.Latitude, a.Longitude, a.Accuracy,
        a.CheckOut, a.OutLatitude, a.OutLongitude, a.ScheduledStart, a.BreakMinutes, a.ExpectedMinutes,
        a.EarlyLeaveGraceMinutes, a.EarlyLeaveMinutes, a.NetMinutes, a.IsAutoClosed, a.AutoClosedAt, a.Status);
}

public sealed class QrService(Microsoft.Extensions.Options.IOptions<AttendanceOptions> options)
{
    public static string NewSecret() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
    private static string Sign(string secret, string data) => Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(data)));
    public QrResponse Create(string secret, DateTime nowUtc)
    {
        var issued = new DateTimeOffset(TimeVn.Utc(nowUtc)).ToUnixTimeSeconds();
        var data = $"BAOAN:{issued}:{Convert.ToHexString(RandomNumberGenerator.GetBytes(16))}";
        return new($"{data}:{Sign(secret, data)}", DateTimeOffset.FromUnixTimeSeconds(issued + options.Value.QrLifetimeSeconds).UtcDateTime);
    }
    public bool IsValid(string secret, string? code, DateTime nowUtc)
    {
        if (string.IsNullOrEmpty(secret) || code == null || code.Length > 200) return false;
        var p = code.Split(':');
        if (p.Length != 4 || p[0] != "BAOAN" || p[2].Length != 32 || p[3].Length != 64 || !long.TryParse(p[1], out var issued)) return false;
        var now = new DateTimeOffset(TimeVn.Utc(nowUtc)).ToUnixTimeSeconds();
        if (issued > now || now - issued >= options.Value.QrLifetimeSeconds) return false;
        return CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(p[3]), Encoding.ASCII.GetBytes(Sign(secret, string.Join(':', p.Take(3)))));
    }
}
