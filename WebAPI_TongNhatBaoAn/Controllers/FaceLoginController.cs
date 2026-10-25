using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Services;

namespace WebAPI_TongNhatBaoAn.Controllers;

public record FaceLoginRequest(string Username, string Image);

/// Face login verifies identity and issues tokens directly.
[ApiController, Route("api/auth"), AllowAnonymous, EnableRateLimiting("auth")]
public class FaceLoginController(AppDb db, FaceMatcher matcher, FaceTemplateCipher cipher, TokenService tokens) : ApiBase
{
    [HttpPost("face-login"), RequestSizeLimit(4_500_000)]
    public async Task<IActionResult> Login(FaceLoginRequest request)
    {
        const string denied = "Không xác thực được tài khoản bằng khuôn mặt. Kiểm tra tên đăng nhập, mẫu đã đăng ký và quyền đăng nhập bằng mặt.";
        var username = (request.Username ?? "").Trim().ToLowerInvariant();
        if (username.Length is < 3 or > 40) return Fail(denied, 401);
        var employee = await db.Employees.FirstOrDefaultAsync(e => e.Username == username);
        if (employee == null || !employee.Active || !employee.EmailVerified) return Fail(denied, 401);
        var profile = await db.FaceProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.EmployeeId == employee.Id);
        if (profile == null || !profile.AllowLogin) return Fail(denied, 401);
        try
        {
            var vector = await matcher.Extract(request.Image);
            if (FaceMath.Cosine(cipher.Decrypt(profile.Template), vector) < FaceMath.Threshold)
                return Fail(denied, 401);
        }
        catch (FaceInputException ex) { return Fail(ex.Message); }
        catch (FaceUnavailableException) { return Fail("Máy chủ nhận diện khuôn mặt chưa sẵn sàng. Bạn có thể dùng mật khẩu + OTP.", 503); }

        // Recheck account after a potentially long model request.
        await db.Entry(employee).ReloadAsync();
        if (db.Entry(employee).State == EntityState.Detached || !employee.Active || !employee.EmailVerified)
            return Fail(denied, 401);
        if (!await db.FaceProfiles.AnyAsync(p => p.EmployeeId == employee.Id && p.AllowLogin && p.UpdatedAt == profile.UpdatedAt))
            return Fail(denied, 401);

        var (access, expires) = tokens.CreateAccess(employee);
        var refresh = tokens.CreateRefresh(employee);
        await db.SaveChangesAsync();
        return Ok(new TokenResponse(access, expires, refresh, EmployeeDto.From(employee)));
    }
}
