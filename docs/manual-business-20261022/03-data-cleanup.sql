-- Preview first. By default every mutation below is rolled back.
-- After verifying the SELECT results, replace the last ROLLBACK with COMMIT to apply.
BEGIN;
CREATE TEMP TABLE cleanup_targets ON COMMIT DROP AS
SELECT "Id" FROM "Employees"
WHERE lower("Username") IN ('apitest','testapi321','vien_test01') AND "Role"<>'admin';

SELECT e."Id",e."Username",e."Name",
    (SELECT COUNT(*) FROM "Attendance" a WHERE a."EmployeeId"=e."Id") AS "AttendanceCount",
    (SELECT COUNT(*) FROM "WorkRequests" w WHERE w."EmployeeId"=e."Id" OR w."ReviewedBy"=e."Id") AS "RequestCount"
FROM "Employees" e JOIN cleanup_targets t ON t."Id"=e."Id";

-- Preserve history/audit references: lock all targeted test accounts first.
UPDATE "Employees" SET "Active"=false WHERE "Id" IN (SELECT "Id" FROM cleanup_targets);
-- Delete only accounts with no attendance, submitted/reviewed requests, or approval audit references.
DELETE FROM "Employees" e WHERE e."Id" IN (SELECT "Id" FROM cleanup_targets)
AND NOT EXISTS (SELECT 1 FROM "Attendance" a WHERE a."EmployeeId"=e."Id")
AND NOT EXISTS (SELECT 1 FROM "WorkRequests" w WHERE w."EmployeeId"=e."Id" OR w."ReviewedBy"=e."Id")
AND NOT EXISTS (SELECT 1 FROM "Employees" other WHERE other."ApprovedBy"=e."Id")
RETURNING "Id","Username";

UPDATE "Employees" SET "Name"='Tống Nhật Bảo An'
WHERE "Role"='admin' AND "Name" IN ('Tổng Nhật Bảo An','Tổng Nhật Bảo An (Admin)');
UPDATE "Offices" SET "Name"='Văn phòng chính' WHERE "Name"='Van phong chinh';
-- Review this radius change before committing; it affects the existing office as well.
UPDATE "Offices" SET "Radius"=100 WHERE "Id"=1 AND "Radius" IN (150,200);
SELECT "Id","Name","Radius" FROM "Offices";
ROLLBACK;
