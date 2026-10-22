using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using WebAPI_TongNhatBaoAn.Data;
using WebAPI_TongNhatBaoAn.Dtos;
using WebAPI_TongNhatBaoAn.Models;
using WebAPI_TongNhatBaoAn.Services;
namespace WebAPI_TongNhatBaoAn.Controllers;

[ApiController, Route("api/requests"), Authorize]
public sealed class RequestsController(AppDb db, IOptions<LeaveOptions> leave, TimeProvider clock) : ApiBase
{
    private static WorkRequestDto Dto(WorkRequest w, string? name) => new(w.Id, w.EmployeeId, name, w.Type,
        w.Reason, w.From, w.To, w.Status, w.ReviewerNote, w.CreatedAt, w.Version, w.Days, w.ReviewedBy, w.ReviewerName, w.ReviewedAt);
    private int Validate(RequestUpsert r)
    {
        if (!RequestTypes.All.Contains(r.Type) || string.IsNullOrWhiteSpace(r.Reason) || r.Reason.Trim().Length < 10)
            throw new BusinessException("Loại đơn không hợp lệ hoặc lý do ít hơn 10 ký tự.");
        var count = BusinessRules.LeaveDays(r.From, r.To, leave.Value);
        if (r.Type == RequestTypes.Leave && count == 0) throw new BusinessException("Khoảng nghỉ chỉ gồm ngày không tính phép.");
        return r.Type == RequestTypes.Leave ? count : 0;
    }
    private async Task<List<WorkRequestDto>> Rows(IQueryable<WorkRequest> q, string? status)
    {
        if (status != null && status is not (RequestStatus.Pending or RequestStatus.Approved or RequestStatus.Rejected))
            throw new BusinessException("Trạng thái đơn không hợp lệ.");
        if (status != null) q = q.Where(w => w.Status == status);
        var rows = await q.AsNoTracking().OrderByDescending(w => w.CreatedAt)
            .Join(db.Employees, w => w.EmployeeId, e => e.Id, (w,e) => new { w, e.Name }).ToListAsync();
        return rows.Select(x => Dto(x.w,x.Name)).ToList();
    }
    [HttpGet("mine")]
    public async Task<IActionResult> Mine(string? status) => Ok(await Rows(db.WorkRequests.Where(w => w.EmployeeId == UserId), status));
    [HttpGet("pending-review"), Authorize(Roles = Roles.AdminOrManager)]
    public async Task<IActionResult> PendingReview()
    {
        var q = db.WorkRequests.Where(w => w.EmployeeId != UserId && w.Status == RequestStatus.Pending);
        // Manager reviews only employee requests; requests from managers/admins need another admin.
        if (!User.IsInRole(Roles.Admin)) q = q.Where(w => db.Employees.Any(e => e.Id == w.EmployeeId && e.Role == Roles.Employee));
        return Ok(await Rows(q, null));
    }
    // Compatibility for existing callers. New integrations use the two explicit endpoints above.
    [HttpGet]
    public async Task<IActionResult> List(string? status) => await Mine(status);
    [HttpPost]
    public Task<IActionResult> Create(RequestUpsert r) => Save(null, r);
    [HttpPatch("{id:guid}")]
    public Task<IActionResult> Update(Guid id, RequestUpsert r) => Save(id, r);
    private async Task<IActionResult> Save(Guid? id, RequestUpsert r)
    {
        var days = Validate(r);
        try
        {
            var result = await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync();
                // Serialize concurrent requests of this employee to protect overlap checks.
                var owner = await db.Employees.FromSqlInterpolated($"SELECT *, xmin FROM \"Employees\" WHERE \"Id\"={UserId} FOR UPDATE").SingleAsync();
                var w = id == null ? new WorkRequest { EmployeeId = UserId, CreatedAt = clock.GetUtcNow().UtcDateTime }
                    : await db.WorkRequests.SingleOrDefaultAsync(w => w.Id == id) ?? throw new BusinessException("Không tìm thấy đơn.", 404);
                if (w.EmployeeId != UserId || w.Status != RequestStatus.Pending) throw new BusinessException("Chỉ sửa đơn của mình đang chờ duyệt.", 403);
                if (r.Type == RequestTypes.Leave && await db.WorkRequests.AnyAsync(x => x.Id != w.Id && x.EmployeeId == UserId &&
                    x.Type == RequestTypes.Leave && x.Status != RequestStatus.Rejected && x.From <= r.To && x.To >= r.From))
                    throw new BusinessException("Khoảng nghỉ trùng với đơn hiện có.", 409);
                w.Type = r.Type; w.Reason = r.Reason.Trim(); w.From = r.From; w.To = r.To; w.Days = days;
                if (id == null) db.WorkRequests.Add(w);
                await db.SaveChangesAsync(); await tx.CommitAsync();
                return Dto(w, owner.Name);
            });
            return id == null ? Created($"/api/requests/{result.Id}", result) : Ok(result);
        }
        catch (DbUpdateConcurrencyException) { return Fail("Đơn vừa được xử lý. Hãy tải lại.", 409); }
    }
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var w = await db.WorkRequests.FindAsync(id);
        if (w == null) return Fail("Không tìm thấy đơn.",404);
        if (w.EmployeeId != UserId || w.Status != RequestStatus.Pending) return Fail("Chỉ xóa đơn của mình đang chờ duyệt.",403);
        db.WorkRequests.Remove(w);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) { return Fail("Đơn vừa được xử lý.",409); }
        return NoContent();
    }
    [HttpPost("{id:guid}/review"), Authorize(Roles = Roles.AdminOrManager)]
    public async Task<IActionResult> Review(Guid id, ReviewRequest r)
    {
        if (string.IsNullOrWhiteSpace(r.Note) || r.Version == null) return Fail("Cần nhận xét và version của đơn.");
        var w = await db.WorkRequests.FindAsync(id);
        if (w == null) return Fail("Không tìm thấy đơn.",404);
        var owner = await db.Employees.FindAsync(w.EmployeeId);
        var reviewer = await db.Employees.FindAsync(UserId);
        if (owner == null || reviewer == null || !BusinessRules.CanReview(UserId, reviewer.Role, owner.Id, owner.Role))
            return Fail("Không được tự duyệt. Đơn quản lý/admin phải do một Admin khác duyệt.",403);
        if (w.Status != RequestStatus.Pending) return Fail("Đơn đã được xử lý.",409);
        db.Entry(w).Property(x => x.Version).OriginalValue = r.Version.Value;
        w.Status = r.Approve ? RequestStatus.Approved : RequestStatus.Rejected;
        w.ReviewedBy = UserId; w.ReviewerName = reviewer.Name;
        w.ReviewedAt = clock.GetUtcNow().UtcDateTime; w.ReviewerNote = r.Note.Trim();
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) { return Fail("Đơn vừa thay đổi. Hãy tải lại.",409); }
        return Ok(Dto(w,owner.Name));
    }
}
