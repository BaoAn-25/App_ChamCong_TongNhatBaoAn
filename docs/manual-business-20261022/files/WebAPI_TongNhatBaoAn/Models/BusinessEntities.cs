namespace WebAPI_TongNhatBaoAn.Models;

public enum ApprovalStatus { PendingApproval, Approved, Rejected }
// Flags: a shift can be both late and leave early. Zero means on time.
[Flags]
public enum AttendanceStatus { DungGio = 0, DiTre = 1, VeSom = 2, QuenCheckOut = 4, BatThuong = 8 }
public class QrRedemption
{
    public Guid EmployeeId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTime RedeemedAt { get; set; }
}
