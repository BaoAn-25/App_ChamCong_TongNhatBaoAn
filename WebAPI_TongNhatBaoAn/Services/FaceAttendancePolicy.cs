using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
namespace WebAPI_TongNhatBaoAn.Services;

public sealed class FaceAttendancePolicy(AppDb db)
{
    public async Task<string?> Consume(Guid employeeId, Guid? proof, string purpose)
    {
        if (!await db.FaceProfiles.AnyAsync(p => p.EmployeeId == employeeId))
            return null; // Explicitly unenrolled users retain the existing QR + GPS flow.
        if (proof == null) return "Tài khoản đã đăng ký khuôn mặt. Hãy xác thực khuôn mặt trước khi chấm công.";
        var now = DateTime.UtcNow;
        var count = await db.FaceGrants.Where(g => g.Id == proof && g.EmployeeId == employeeId &&
            g.Purpose == purpose && !g.Consumed && g.ExpiresAt > now)
            .ExecuteUpdateAsync(setters => setters.SetProperty(g => g.Consumed, true));
        return count == 1 ? null : "Xác thực khuôn mặt đã hết hạn hoặc đã dùng. Hãy chụp lại.";
    }
}
