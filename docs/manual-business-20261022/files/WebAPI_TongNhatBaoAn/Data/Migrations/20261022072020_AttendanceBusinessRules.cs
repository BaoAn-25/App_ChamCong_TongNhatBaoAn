using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WebAPI_TongNhatBaoAn.Data.Migrations
{
    /// <inheritdoc />
    public partial class AttendanceBusinessRules : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Days",
                table: "WorkRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "ReviewedAt",
                table: "WorkRequests",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ReviewerName",
                table: "WorkRequests",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "BreakMinutes",
                table: "Shifts",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "EarlyLeaveGraceMinutes",
                table: "Shifts",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AlterColumn<double>(
                name: "Radius",
                table: "Offices",
                type: "double precision",
                nullable: false,
                defaultValue: 100.0,
                oldClrType: typeof(double),
                oldType: "double precision");

            migrationBuilder.AddColumn<string>(
                name: "ApprovalNote",
                table: "Employees",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "ApprovalStatus",
                table: "Employees",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<DateTime>(
                name: "ApprovedAt",
                table: "Employees",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ApprovedBy",
                table: "Employees",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<uint>(
                name: "xmin",
                table: "Employees",
                type: "xid",
                rowVersion: true,
                nullable: false,
                defaultValue: 0u);

            migrationBuilder.AddColumn<DateTime>(
                name: "AutoCloseAt",
                table: "Attendance",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<DateTime>(
                name: "AutoClosedAt",
                table: "Attendance",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "BreakMinutes",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "EarlyLeaveGraceMinutes",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "EarlyLeaveMinutes",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "ExpectedMinutes",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<bool>(
                name: "IsAutoClosed",
                table: "Attendance",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "NetMinutes",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "ScheduledStart",
                table: "Attendance",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<int>(
                name: "Status",
                table: "Attendance",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<uint>(
                name: "xmin",
                table: "Attendance",
                type: "xid",
                rowVersion: true,
                nullable: false,
                defaultValue: 0u);

            migrationBuilder.CreateTable(
                name: "QrRedemptions",
                columns: table => new
                {
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    RedeemedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_QrRedemptions", x => new { x.EmployeeId, x.TokenHash });
                    table.ForeignKey(
                        name: "FK_QrRedemptions_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_QrRedemptions_RedeemedAt",
                table: "QrRedemptions",
                column: "RedeemedAt");
            migrationBuilder.Sql("""
-- Existing accounts remain usable after migration. Public registration explicitly creates PendingApproval.
UPDATE "Employees" SET "ApprovalStatus"='Approved' WHERE "ApprovalStatus"='';
UPDATE "Shifts" SET "EarlyLeaveGraceMinutes"=5;

-- Historical rows lack immutable shift snapshots. Preserve all original instants;
-- quarantine for review rather than inventing a start time/break or counting unreliable hours.
UPDATE "Attendance" SET
    "ScheduledStart"="CheckIn",
    "AutoCloseAt"=((("ScheduledEnd" AT TIME ZONE 'Asia/Ho_Chi_Minh')::date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'),
    "Status"=8 | CASE WHEN "LateMinutes">0 THEN 1 ELSE 0 END,
    "NetMinutes"=CASE WHEN "CheckOut" IS NULL THEN 0 ELSE GREATEST(0,FLOOR(EXTRACT(EPOCH FROM ("CheckOut"-"CheckIn"))/60)::integer) END;

UPDATE "WorkRequests" w SET "ReviewerName"=e."Name"
FROM "Employees" e WHERE w."ReviewedBy"=e."Id";
-- ReviewedAt is deliberately NULL for legacy requests: the old system did not record it.
-- Default policy at migration: exclude Saturday/Sunday. New requests use Leave__ExcludedDays.
UPDATE "WorkRequests" w SET "Days"=(
    SELECT COUNT(*) FROM generate_series(w."From"::timestamp,w."To"::timestamp,interval '1 day') AS d(day)
    WHERE EXTRACT(ISODOW FROM d.day)<6
) WHERE w."Type"='Nghỉ phép';

UPDATE "Employees" SET "Name"='Tống Nhật Bảo An'
WHERE "Role"='admin' AND "Name" IN ('Tổng Nhật Bảo An','Tổng Nhật Bảo An (Admin)');
UPDATE "Offices" SET "Name"='Văn phòng chính' WHERE "Name"='Van phong chinh';

""");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "QrRedemptions");

            migrationBuilder.DropColumn(
                name: "Days",
                table: "WorkRequests");

            migrationBuilder.DropColumn(
                name: "ReviewedAt",
                table: "WorkRequests");

            migrationBuilder.DropColumn(
                name: "ReviewerName",
                table: "WorkRequests");

            migrationBuilder.DropColumn(
                name: "BreakMinutes",
                table: "Shifts");

            migrationBuilder.DropColumn(
                name: "EarlyLeaveGraceMinutes",
                table: "Shifts");

            migrationBuilder.DropColumn(
                name: "ApprovalNote",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "ApprovalStatus",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "ApprovedAt",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "ApprovedBy",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "xmin",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "AutoCloseAt",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "AutoClosedAt",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "BreakMinutes",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "EarlyLeaveGraceMinutes",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "EarlyLeaveMinutes",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "ExpectedMinutes",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "IsAutoClosed",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "NetMinutes",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "ScheduledStart",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "Attendance");

            migrationBuilder.DropColumn(
                name: "xmin",
                table: "Attendance");

            migrationBuilder.AlterColumn<double>(
                name: "Radius",
                table: "Offices",
                type: "double precision",
                nullable: false,
                oldClrType: typeof(double),
                oldType: "double precision",
                oldDefaultValue: 100.0);
        }
    }
}
