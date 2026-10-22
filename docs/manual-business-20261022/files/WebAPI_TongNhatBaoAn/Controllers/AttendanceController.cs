using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;
using WebAPI_TongNhatBaoAn.Services;
namespace WebAPI_TongNhatBaoAn.Controllers;

[ApiController, Route("api/attendance"), Authorize]
public sealed class AttendanceController(AppDb db, AttendanceService service) : ApiBase
{
    [HttpPost("check-in")]
    public async Task<IActionResult> CheckIn(PunchRequest r) => Ok(await service.PunchAsync(UserId, r, true));
    [HttpPost("check-out")]
    public async Task<IActionResult> CheckOut(PunchRequest r) => Ok(await service.PunchAsync(UserId, r, false));
    [HttpGet]
    public async Task<IActionResult> List(DateOnly? from, DateOnly? to, Guid? employeeId, int page = 1, int pageSize = 50)
    {
        if (from > to || from?.Year is < 1970 or > 9998 || to?.Year is < 1970 or > 9998)
            return Fail("Khoảng ngày không hợp lệ.");
        await service.CloseOverdueAsync();
        page = Math.Clamp(page, 1, 1000000); pageSize = Math.Clamp(pageSize, 1, 100);
        var scope = User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Manager) ? employeeId : UserId;
        var q = db.Attendance.AsNoTracking();
        if (scope != null) q = q.Where(a => a.EmployeeId == scope);
        if (from != null) { var lower = TimeVn.ToUtc(from.Value.ToDateTime(TimeOnly.MinValue)); q = q.Where(a => a.CheckIn >= lower); }
        if (to != null) { var upper = TimeVn.ToUtc(to.Value.AddDays(1).ToDateTime(TimeOnly.MinValue)); q = q.Where(a => a.CheckIn < upper); }
        var total = await q.CountAsync();
        var rows = await q.OrderByDescending(a => a.CheckIn).ThenByDescending(a => a.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Join(db.Employees, a => a.EmployeeId, e => e.Id, (a,e) => new { a, e.Name }).ToListAsync();
        return Ok(new PagedResult<AttendanceDto>(total, page, pageSize, rows.Select(x => BusinessRules.Dto(x.a, x.Name)).ToList()));
    }
}
