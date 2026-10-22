using WebAPI_TongNhatBaoAn.Models;

namespace WebAPI_TongNhatBaoAn.Dtos;

public record RegisterRequest(string Name, string Email, string Username, string Password);
public record VerifyCodeRequest(Guid ChallengeId, string Code);
public record LoginRequest(string Username, string Password);
public record RefreshRequest(string RefreshToken);
public record ChallengeResponse(Guid ChallengeId, string? DebugCode = null);

public record EmployeeDto(Guid Id, string Name, string Email, string Username, string Department,
    string Role, Guid? ShiftId, bool Active, ApprovalStatus ApprovalStatus)
{
    public static EmployeeDto From(Employee e) =>
        new(e.Id, e.Name, e.Email, e.Username, e.Department, e.Role, e.ShiftId, e.Active, e.ApprovalStatus);
}

public record TokenResponse(string AccessToken, DateTime AccessExpiresAt, string RefreshToken, EmployeeDto User);

public record EmployeeCreate(string Name, string Email, string Username, string Password,
    string? Department, string? Role, Guid? ShiftId);
public record EmployeeUpdate(string? Name, string? Email, string? Username, string? Password,
    string? Department, string? Role, bool? Active);
public record AssignShift(Guid? ShiftId);

public record ShiftDto(Guid Id, string Name, int StartMinute, int EndMinute, int Grace, int BreakMinutes, int EarlyLeaveGraceMinutes)
{
    public static ShiftDto From(Shift s) => new(s.Id, s.Name, s.StartMinute, s.EndMinute, s.Grace, s.BreakMinutes, s.EarlyLeaveGraceMinutes);
}
public record ShiftUpsert(string Name, int StartMinute, int EndMinute, int Grace, int? BreakMinutes = null, int? EarlyLeaveGraceMinutes = null);

public record DepartmentDto(Guid Id, string Name, string? Description)
{
    public static DepartmentDto From(Department d) => new(d.Id, d.Name, d.Description);
}
public record DepartmentUpsert(string Name, string? Description);

public record OfficeDto(string Name, double? Latitude, double? Longitude, double Radius, bool Configured)
{
    public static OfficeDto From(Office o) => new(o.Name, o.Latitude, o.Longitude, o.Radius, o.Configured);
}
public record OfficeUpdate(string Name, double Latitude, double Longitude, double Radius);
public record QrResponse(string Code, DateTime ExpiresAt);

public record PunchRequest(string Qr, double Latitude, double Longitude, double Accuracy,
    DateTime CapturedAt, string IdempotencyKey, bool IsMocked = false, Guid? FaceProof = null);

public record AttendanceDto(Guid Id, Guid EmployeeId, string? EmployeeName, string ShiftName, string WorkDate,
    DateTime CheckIn, DateTime ScheduledEnd, int LateMinutes, double Latitude, double Longitude,
    double Accuracy, DateTime? CheckOut, double? OutLatitude, double? OutLongitude,
    DateTime ScheduledStart, int BreakMinutes, int ExpectedMinutes, int EarlyLeaveGraceMinutes,
    int EarlyLeaveMinutes, int NetMinutes, bool IsAutoClosed, DateTime? AutoClosedAt, AttendanceStatus Status);
public record PagedResult<T>(int Total, int Page, int PageSize, List<T> Items);

public record RequestUpsert(string Type, string Reason, DateOnly From, DateOnly To);
public record ReviewRequest(bool Approve, string Note, uint? Version);
public record WorkRequestDto(Guid Id, Guid EmployeeId, string? EmployeeName, string Type, string Reason,
    DateOnly From, DateOnly To, string Status, string ReviewerNote, DateTime CreatedAt, uint Version, int Days, Guid? ReviewedBy, string? ReviewerName, DateTime? ReviewedAt);
