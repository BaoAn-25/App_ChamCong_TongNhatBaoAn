using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Models;
using WebAPI_TongNhatBaoAn.Services;

namespace WebAPI_TongNhatBaoAn.Controllers;

public record FaceEnrollRequest(Guid ChallengeId, string Code, string Image, string ConfirmImage, bool Consent, bool AllowLogin = false);
public record FaceVerifyRequest(string Image, string Purpose);
public record FaceDeleteRequest(Guid ChallengeId, string Code);

[ApiController, Route("api/face"), Authorize, EnableRateLimiting("face")]
public class FaceController(AppDb db, OtpService otp, FaceMatcher matcher, FaceTemplateCipher cipher) : ApiBase
{
    private const string Enrollment = "face-enrollment";

    [HttpGet("status")]
    public async Task<IActionResult> Status()
    {
        var profile = await db.FaceProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.EmployeeId == UserId);
        return Ok(new { enrolled = profile != null, allowLogin = profile?.AllowLogin ?? false });
    }

    [HttpPost("request-otp")]
    public async Task<IActionResult> RequestOtp()
    {
        var employee = await db.Employees.FindAsync(UserId);
        if (employee == null || !employee.Active || !employee.EmailVerified) return Fail("Vui lòng đăng nhập lại.", 401);
        var (challenge, code) = otp.Create(UserId, Enrollment);
        await db.SaveChangesAsync();
        try { await otp.SendAsync(employee.Email, "Xác nhận quản lý mẫu khuôn mặt", code); }
        catch (OtpDeliveryException)
        {
            challenge.Consumed = true;
            await db.SaveChangesAsync();
            return Fail(OtpDeliveryException.PublicMessage, 503);
        }
        return Ok(new { challengeId = challenge.Id, email = employee.Email });
    }

    private async Task<bool> OwnChallenge(Guid id) =>
        await db.OtpChallenges.AnyAsync(c => c.Id == id && c.EmployeeId == UserId && c.Purpose == Enrollment);

    [HttpPost("enroll"), RequestSizeLimit(9_000_000)]
    public async Task<IActionResult> Enroll(FaceEnrollRequest r)
    {
        if (!r.Consent) return Fail("Cần đồng ý lưu mẫu khuôn mặt để bật chức năng này.");
        if (!await OwnChallenge(r.ChallengeId)) return Fail("Phiên xác nhận không hợp lệ.", 400);
        // Verify ownership before invoking the image processor.
        var (employee, error) = await otp.VerifyAsync(r.ChallengeId, r.Code, Enrollment);
        if (employee == null) return Fail(error!, 400);
        try
        {
            var vector = await matcher.Extract(r.Image);
            var confirm = await matcher.Extract(r.ConfirmImage);
            if (FaceMath.Cosine(vector, confirm) < FaceMath.Threshold)
                return Fail("Hai ảnh không khớp cùng một người. Xin OTP mới và chụp lại.");
            var profile = await db.FaceProfiles.FindAsync(UserId);
            if (profile == null) { profile = new FaceProfile { EmployeeId = UserId }; db.FaceProfiles.Add(profile); }
            profile.Template = cipher.Encrypt(vector);
            profile.AllowLogin = r.AllowLogin;
            profile.UpdatedAt = DateTime.UtcNow;
            await db.FaceGrants.Where(g => g.EmployeeId == UserId).ExecuteDeleteAsync();
            await db.SaveChangesAsync();
            return Ok(new { enrolled = true });
        }
        catch (FaceInputException ex) { return Fail(ex.Message + " Hãy xin OTP mới để thử lại."); }
        catch (FaceUnavailableException) { return Fail("Bộ xử lý khuôn mặt chưa sẵn sàng. Kiểm tra triển khai server và xin OTP mới để thử lại.", 503); }
    }

    [HttpPost("verify"), RequestSizeLimit(4_500_000)]
    public async Task<IActionResult> Verify(FaceVerifyRequest r)
    {
        if (r.Purpose is not ("check-in" or "check-out")) return Fail("Mục đích xác thực không hợp lệ.");
        var profile = await db.FaceProfiles.FindAsync(UserId);
        if (profile == null) return Fail("Bạn chưa đăng ký mẫu khuôn mặt.", 409);
        try
        {
            var vector = await matcher.Extract(r.Image);
            if (FaceMath.Cosine(cipher.Decrypt(profile.Template), vector) < FaceMath.Threshold)
                return Fail("Khuôn mặt không khớp tài khoản đang đăng nhập.", 403);
            var now = DateTime.UtcNow;
            await db.FaceGrants.Where(g => g.EmployeeId == UserId && (g.Consumed || g.ExpiresAt <= now)).ExecuteDeleteAsync();
            var grant = new FaceGrant { EmployeeId = UserId, Purpose = r.Purpose, ExpiresAt = now.AddSeconds(90) };
            db.FaceGrants.Add(grant);
            await db.SaveChangesAsync();
            return Ok(new { proof = grant.Id, expiresAt = grant.ExpiresAt });
        }
        catch (FaceInputException ex) { return Fail(ex.Message); }
        catch (FaceUnavailableException) { return Fail("Bộ xử lý khuôn mặt chưa sẵn sàng. Vui lòng thử lại sau.", 503); }
    }

    [HttpPost("remove")]
    public async Task<IActionResult> Remove(FaceDeleteRequest r)
    {
        if (!await OwnChallenge(r.ChallengeId)) return Fail("Phiên xác nhận không hợp lệ.");
        var (employee, error) = await otp.VerifyAsync(r.ChallengeId, r.Code, Enrollment);
        if (employee == null) return Fail(error!, 400);
        await db.FaceGrants.Where(g => g.EmployeeId == UserId).ExecuteDeleteAsync();
        await db.FaceProfiles.Where(p => p.EmployeeId == UserId).ExecuteDeleteAsync();
        return Ok(new { enrolled = false });
    }
}
