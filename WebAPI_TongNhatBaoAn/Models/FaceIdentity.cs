namespace WebAPI_TongNhatBaoAn.Models;

public class FaceProfile
{
    public Guid EmployeeId { get; set; }
    public string Template { get; set; } = "";
    public bool AllowLogin { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class FaceGrant
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EmployeeId { get; set; }
    public string Purpose { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public bool Consumed { get; set; }
}
