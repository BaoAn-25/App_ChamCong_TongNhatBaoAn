using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;
namespace WebAPI_TongNhatBaoAn.Controllers;

public record ApprovalReview(bool Approve, string Note, uint Version);
[ApiController, Route("api/registrations"), Authorize(Roles = Roles.Admin)]
public sealed class ApprovalController(AppDb db) : ApiBase
{
    [HttpGet("pending")]
    public async Task<IActionResult> Pending() => Ok(await db.Employees.AsNoTracking()
        .Where(e => e.ApprovalStatus == ApprovalStatus.PendingApproval && e.EmailVerified)
        .OrderBy(e => e.CreatedAt).Select(e => new { user = EmployeeDto.From(e), e.Version }).ToListAsync());
    [HttpPost("{id:guid}/review")]
    public async Task<IActionResult> Review(Guid id, ApprovalReview r)
    {
        var employee = await db.Employees.FindAsync(id);
        if (employee == null) return Fail("Không tìm thấy tài khoản.",404);
        if (employee.Id == UserId || !employee.EmailVerified || employee.ApprovalStatus != ApprovalStatus.PendingApproval)
            return Fail("Chỉ duyệt tài khoản đã xác minh email và đang chờ duyệt.",409);
        if (string.IsNullOrWhiteSpace(r.Note)) return Fail("Nhập ghi chú duyệt hoặc từ chối.");
        db.Entry(employee).Property(e => e.Version).OriginalValue = r.Version;
        employee.Role = Roles.Employee;
        employee.ApprovalStatus = r.Approve ? ApprovalStatus.Approved : ApprovalStatus.Rejected;
        employee.ApprovedBy = UserId; employee.ApprovedAt = DateTime.UtcNow; employee.ApprovalNote = r.Note.Trim();
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) { return Fail("Tài khoản vừa được xử lý. Hãy tải lại.",409); }
        return Ok(EmployeeDto.From(employee));
    }
}
