using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;
using WebAPI_TongNhatBaoAn.Services;

namespace WebAPI_TongNhatBaoAn.Controllers;

public abstract class ApiBase : ControllerBase
{
    protected Guid UserId => Guid.Parse(User.FindFirstValue("uid")!);
    protected IActionResult Fail(string message, int status = 400) => StatusCode(status, new { error = message });
}

[ApiController, Route("api/auth"), EnableRateLimiting("auth")]
public class AuthController(AppDb db, TokenService tokens, OtpService otp) : ApiBase
{
    private const string Verify = "verify-email", Login = "login";
    private static readonly string DummyHash = BCrypt.Net.BCrypt.HashPassword("dummy-password");

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest r)
    {
        var err = Validators.Employee(r.Name, r.Username, r.Email, r.Password);
        if (err != null) return Fail(err);
        var username = r.Username.Trim().ToLowerInvariant();
        var email = r.Email.Trim().ToLowerInvariant();
        var existing = await db.Employees.FirstOrDefaultAsync(e => e.Username == username || e.Email == email);
        // Recover an interrupted registration only with the original credentials.
        if (existing != null && (existing.Username != username || existing.Email != email ||
            existing.EmailVerified || !existing.Active || !BCrypt.Net.BCrypt.Verify(r.Password, existing.PasswordHash)))
            return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409);

        var emp = existing ?? new Employee
        {
            Name = r.Name.Trim(), Email = email, Username = username,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(r.Password), Role = Roles.Employee,
            ApprovalStatus = ApprovalStatus.PendingApproval
        };
        if (existing == null) db.Employees.Add(emp);
        var (challenge, code) = otp.Create(emp.Id, Verify);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) { return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409); }
        try { await otp.SendAsync(emp.Email, "Xác minh email đăng ký", code); }
        catch (OtpDeliveryException)
        {
            // Allow registration to be retried after delivery failure.
            db.OtpChallenges.Remove(challenge);
            if (existing == null) db.Employees.Remove(emp);
            await db.SaveChangesAsync();
            return Fail(OtpDeliveryException.PublicMessage, 503);
        }
        return Ok(new ChallengeResponse(challenge.Id, otp.DebugReturn ? code : null));
    }

    [HttpPost("verify-email")]
    public async Task<IActionResult> VerifyEmail(VerifyCodeRequest r)
    {
        var (emp, error) = await otp.VerifyAsync(r.ChallengeId, r.Code, Verify);
        if (emp == null) return Fail(error!, 400);
        emp.EmailVerified = true;
        await db.SaveChangesAsync();
        return Ok(new { verified = true, approvalStatus = emp.ApprovalStatus, message = "Email đã xác minh. Tài khoản cần Admin duyệt trước khi đăng nhập." });
    }

    [HttpPost("login")]
    public async Task<IActionResult> LoginStep1(LoginRequest r)
    {
        var username = (r.Username ?? "").Trim().ToLowerInvariant();
        var emp = await db.Employees.FirstOrDefaultAsync(e => e.Username == username);
        var passwordOk = BCrypt.Net.BCrypt.Verify(r.Password ?? "", emp?.PasswordHash ?? DummyHash);
        if (emp == null || !passwordOk || !emp.Active || !emp.EmailVerified)
            return Fail("Tên đăng nhập hoặc mật khẩu không đúng, tài khoản bị khóa hoặc chưa xác minh email.", 401);

        if (emp.ApprovalStatus != ApprovalStatus.Approved) return Fail("Tài khoản đang chờ duyệt hoặc đã bị từ chối. Liên hệ Admin.", 403);
        var (challenge, code) = otp.Create(emp.Id, Login);
        await db.SaveChangesAsync();
        try { await otp.SendAsync(emp.Email, "Mã OTP đăng nhập", code); }
        catch (OtpDeliveryException)
        {
            challenge.Consumed = true;
            await db.SaveChangesAsync();
            return Fail(OtpDeliveryException.PublicMessage, 503);
        }
        return Ok(new ChallengeResponse(challenge.Id, otp.DebugReturn ? code : null));
    }

    [HttpPost("verify-otp")]
    public async Task<IActionResult> VerifyOtp(VerifyCodeRequest r)
    {
        var (emp, error) = await otp.VerifyAsync(r.ChallengeId, r.Code, Login);
        if (emp == null) return Fail(error!, 401);
        if (!BusinessRules.CanUse(emp)) return Fail("Tài khoản bị khóa hoặc chưa xác minh email.", 403);
        return Ok(await IssueAsync(emp));
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(RefreshRequest r)
    {
        var hash = TokenService.Hash(r.RefreshToken ?? "");
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash);
        if (stored == null || stored.Revoked || stored.ExpiresAt < DateTime.UtcNow)
            return Fail("Phiên đăng nhập hết hạn.", 401);
        var emp = await db.Employees.FindAsync(stored.EmployeeId);
        if (emp == null || !BusinessRules.CanUse(emp)) return Fail("Phiên đăng nhập hết hạn.", 401);
        stored.Revoked = true;
        return Ok(await IssueAsync(emp));
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout(RefreshRequest r)
    {
        var hash = TokenService.Hash(r.RefreshToken ?? "");
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash);
        if (stored != null) { stored.Revoked = true; await db.SaveChangesAsync(); }
        return NoContent();
    }

    private async Task<TokenResponse> IssueAsync(Employee emp)
    {
        var (access, expires) = tokens.CreateAccess(emp);
        var refresh = tokens.CreateRefresh(emp);
        await db.SaveChangesAsync();
        return new TokenResponse(access, expires, refresh, EmployeeDto.From(emp));
    }
}

[ApiController, Route("api/me"), Authorize]
public class MeController(AppDb db) : ApiBase
{
    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var emp = await db.Employees.FindAsync(UserId);
        return emp == null || !BusinessRules.CanUse(emp) ? Fail("Vui lòng đăng nhập lại.", 401) : Ok(EmployeeDto.From(emp));
    }
}

[ApiController, Route("api/employees"), Authorize(Roles = Roles.AdminOrManager)]
public class EmployeesController(AppDb db) : ApiBase
{
    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.Employees.OrderBy(e => e.Name).Select(e => EmployeeDto.From(e)).ToListAsync());

    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create(EmployeeCreate r)
    {
        var err = Validators.Employee(r.Name, r.Username, r.Email, r.Password ?? "");
        if (err != null) return Fail(err);
        var role = (r.Role ?? Roles.Employee).ToLowerInvariant();
        if (!Roles.IsValid(role)) return Fail("Vai trò không hợp lệ.");
        if (r.ShiftId != null && !await db.Shifts.AnyAsync(s => s.Id == r.ShiftId)) return Fail("Ca làm không tồn tại.");
        var username = r.Username.Trim().ToLowerInvariant();
        var email = r.Email.Trim().ToLowerInvariant();
        if (await db.Employees.AnyAsync(e => e.Username == username || e.Email == email))
            return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409);

        var emp = new Employee
        {
            Name = r.Name.Trim(), Email = email, Username = username, Department = r.Department?.Trim() ?? "",
            Role = role, ShiftId = r.ShiftId, EmailVerified = true, ApprovalStatus = ApprovalStatus.Approved,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(r.Password)
        };
        db.Employees.Add(emp);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) { return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409); }
        return Created($"/api/employees/{emp.Id}", EmployeeDto.From(emp));
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, EmployeeUpdate r)
    {
        var isAdmin = User.IsInRole(Roles.Admin);
        if (!isAdmin && id != UserId) return Forbid();

        var emp = await db.Employees.FindAsync(id);
        if (emp == null) return Fail("Không tìm thấy nhân viên.", 404);
        var name = r.Name ?? emp.Name;
        var username = (r.Username ?? emp.Username).Trim().ToLowerInvariant();
        var email = (r.Email ?? emp.Email).Trim().ToLowerInvariant();
        var err = Validators.Employee(name, username, email, string.IsNullOrEmpty(r.Password) ? null : r.Password);
        if (err != null) return Fail(err);

        var role = isAdmin ? (r.Role ?? emp.Role).ToLowerInvariant() : emp.Role;
        if (!Roles.IsValid(role)) return Fail("Vai trò không hợp lệ.");
        var active = isAdmin ? (r.Active ?? emp.Active) : emp.Active;
        if (isAdmin && id == UserId && (!active || role != Roles.Admin)) return Fail("Không được khóa hoặc hạ quyền chính mình.", 409);
        if (await db.Employees.AnyAsync(e => e.Id != id && (e.Username == username || e.Email == email)))
            return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409);

        emp.Name = name.Trim(); emp.Username = username; emp.Email = email; emp.Role = role; emp.Active = active;
        if (isAdmin && r.Department != null) emp.Department = r.Department.Trim();
        if (!string.IsNullOrEmpty(r.Password)) emp.PasswordHash = BCrypt.Net.BCrypt.HashPassword(r.Password);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) { return Fail("Email hoặc tên đăng nhập đã tồn tại.", 409); }
        return Ok(EmployeeDto.From(emp));
    }

    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (id == UserId) return Fail("Không thể xóa tài khoản đang đăng nhập.", 409);
        var emp = await db.Employees.FindAsync(id);
        if (emp == null) return Fail("Không tìm thấy nhân viên.", 404);
        if (await db.Attendance.AnyAsync(a => a.EmployeeId == id) || await db.WorkRequests.AnyAsync(r => r.EmployeeId == id))
            return Fail("Nhân viên đã có lịch sử. Hãy khóa tài khoản để giữ dữ liệu.", 409);
        db.Employees.Remove(emp);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPut("{id:guid}/shift"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> AssignShift(Guid id, AssignShift r)
    {
        var emp = await db.Employees.FindAsync(id);
        if (emp == null) return Fail("Không tìm thấy nhân viên.", 404);
        if (r.ShiftId != null && !await db.Shifts.AnyAsync(s => s.Id == r.ShiftId)) return Fail("Ca làm không tồn tại.");
        emp.ShiftId = r.ShiftId;
        await db.SaveChangesAsync();
        return Ok(EmployeeDto.From(emp));
    }
}

[ApiController, Route("api/shifts"), Authorize]
public class ShiftsController(AppDb db) : ApiBase
{
    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.Shifts.OrderBy(s => s.StartMinute).Select(s => ShiftDto.From(s)).ToListAsync());

    private static string? Check(ShiftUpsert r) =>
        string.IsNullOrWhiteSpace(r.Name) || r.StartMinute is < 0 or >= 1440 || r.EndMinute is < 0 or >= 1440 ||
        r.StartMinute == r.EndMinute || r.Grace is < 0 or > 60 || r.BreakMinutes is < 0 ||
        r.BreakMinutes.GetValueOrDefault() >= (r.EndMinute-r.StartMinute+1440)%1440 || r.EarlyLeaveGraceMinutes is < 0 or > 60
            ? "Ca phải có tên, giờ vào/ra khác nhau và dung sai từ 0–60 phút."
            : null;

    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create(ShiftUpsert r)
    {
        var err = Check(r);
        if (err != null) return Fail(err);
        var s = new Shift { Name = r.Name.Trim(), StartMinute = r.StartMinute, EndMinute = r.EndMinute, Grace = r.Grace, BreakMinutes = r.BreakMinutes ?? 0, EarlyLeaveGraceMinutes = r.EarlyLeaveGraceMinutes ?? 5 };
        db.Shifts.Add(s);
        await db.SaveChangesAsync();
        return Created($"/api/shifts/{s.Id}", ShiftDto.From(s));
    }

    [HttpPatch("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Update(Guid id, ShiftUpsert r)
    {
        var err = Check(r);
        if (err != null) return Fail(err);
        var s = await db.Shifts.FindAsync(id);
        if (s == null) return Fail("Không tìm thấy ca.", 404);
        if ((r.BreakMinutes ?? s.BreakMinutes) >= (r.EndMinute-r.StartMinute+1440)%1440) return Fail("Thời gian nghỉ phải ngắn hơn ca.");
        s.Name = r.Name.Trim(); s.StartMinute = r.StartMinute; s.EndMinute = r.EndMinute; s.Grace = r.Grace; s.BreakMinutes = r.BreakMinutes ?? s.BreakMinutes; s.EarlyLeaveGraceMinutes = r.EarlyLeaveGraceMinutes ?? s.EarlyLeaveGraceMinutes;
        await db.SaveChangesAsync();
        return Ok(ShiftDto.From(s));
    }

    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(Guid id, [FromQuery] bool force = false)
    {
        var s = await db.Shifts.FindAsync(id);
        if (s == null) return Fail("Không tìm thấy ca.", 404);
        var assigned = await db.Employees.Where(e => e.ShiftId == id).ToListAsync();
        if (assigned.Count > 0)
        {
            if (!force)
            {
                var names = string.Join(", ", assigned.Take(3).Select(e => e.Name));
                var extra = assigned.Count > 3 ? $" và {assigned.Count - 3} người khác" : "";
                return Fail($"Ca đang được phân công cho {assigned.Count} nhân viên ({names}{extra}). Hãy bỏ phân công trước khi xóa.", 409);
            }
            foreach (var e in assigned) e.ShiftId = null;
        }
        db.Shifts.Remove(s);
        await db.SaveChangesAsync();
        return NoContent();
    }
}

[ApiController, Route("api/departments"), Authorize]
public class DepartmentsController(AppDb db) : ApiBase
{
    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.Departments.OrderBy(d => d.Name).Select(d => DepartmentDto.From(d)).ToListAsync());

    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create(DepartmentUpsert r)
    {
        var name = (r.Name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name)) return Fail("Tên phòng ban không được để trống.");
        if (await db.Departments.AnyAsync(d => d.Name.ToLower() == name.ToLower()))
            return Fail("Phòng ban này đã tồn tại.", 409);
        var d = new Department { Name = name, Description = r.Description?.Trim() };
        db.Departments.Add(d);
        await db.SaveChangesAsync();
        return Created($"/api/departments/{d.Id}", DepartmentDto.From(d));
    }

    [HttpPatch("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Update(Guid id, DepartmentUpsert r)
    {
        var name = (r.Name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name)) return Fail("Tên phòng ban không được để trống.");
        var d = await db.Departments.FindAsync(id);
        if (d == null) return Fail("Không tìm thấy phòng ban.", 404);
        if (await db.Departments.AnyAsync(x => x.Id != id && x.Name.ToLower() == name.ToLower()))
            return Fail("Tên phòng ban đã trùng với phòng ban khác.", 409);

        var oldName = d.Name;
        d.Name = name;
        d.Description = r.Description?.Trim();

        if (oldName != name)
        {
            var emps = await db.Employees.Where(e => e.Department == oldName).ToListAsync();
            foreach (var e in emps) e.Department = name;
        }

        await db.SaveChangesAsync();
        return Ok(DepartmentDto.From(d));
    }

    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(Guid id)
    {
        var d = await db.Departments.FindAsync(id);
        if (d == null) return Fail("Không tìm thấy phòng ban.", 404);
        if (await db.Employees.AnyAsync(e => e.Department == d.Name))
            return Fail($"Phòng ban '{d.Name}' đang có nhân viên trực thuộc. Hãy chuyển phòng ban cho nhân viên trước khi xóa.", 409);
        db.Departments.Remove(d);
        await db.SaveChangesAsync();
        return NoContent();
    }
}

[ApiController, Route("api/office"), Authorize]
public class OfficeController(AppDb db, QrService qr) : ApiBase
{
    private async Task<Office> GetOfficeAsync()
    {
        var o = await db.Offices.FindAsync(1);
        if (o != null) return o;
        o = new Office { QrSecret = QrService.NewSecret() };
        db.Offices.Add(o);
        await db.SaveChangesAsync();
        return o;
    }

    [HttpGet]
    public async Task<IActionResult> Get() => Ok(OfficeDto.From(await GetOfficeAsync()));

    [HttpPut, Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Update(OfficeUpdate r)
    {
        if (string.IsNullOrWhiteSpace(r.Name) || !double.IsFinite(r.Latitude) || !double.IsFinite(r.Longitude) ||
            Math.Abs(r.Latitude) > 90 || Math.Abs(r.Longitude) > 180 || !double.IsFinite(r.Radius) ||
            r.Radius is < 20 or > 5000)
            return Fail("Nhập tọa độ hợp lệ và bán kính 20–5000 mét.");
        var o = await GetOfficeAsync();
        o.Name = r.Name.Trim(); o.Latitude = r.Latitude; o.Longitude = r.Longitude; o.Radius = r.Radius;
        if (o.QrSecret.Length == 0) o.QrSecret = QrService.NewSecret();
        await db.SaveChangesAsync();
        return Ok(OfficeDto.From(o));
    }

    [HttpPost("qr"), Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> CreateQr()
    {
        var o = await GetOfficeAsync();
        if (!o.Configured) return Fail("Chưa cấu hình văn phòng.", 409);
        return Ok(qr.Create(o.QrSecret, DateTime.UtcNow));
    }
}

