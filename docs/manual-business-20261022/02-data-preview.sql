SET TIME ZONE 'UTC';
SELECT "MigrationId" FROM "__EFMigrationsHistory" ORDER BY "MigrationId";
SELECT table_name,column_name,data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('Attendance','Employees','WorkRequests')
AND (column_name LIKE '%At' OR column_name IN ('CheckIn','CheckOut','ScheduledEnd','ScheduledStart'));

SELECT "Id","Name","Radius" FROM "Offices";
SELECT "Id","Name","Username","Active","ApprovalStatus" FROM "Employees"
WHERE lower("Username") IN ('apitest','testapi321','vien_test01') OR "Role"='admin';
SELECT "Id","CheckIn","CheckIn" AT TIME ZONE 'Asia/Ho_Chi_Minh' AS "CheckInVn",
       "CheckOut","Status","NetMinutes" FROM "Attendance" ORDER BY "CheckIn" DESC LIMIT 30;

-- Approved, verified and unlocked non-admin accounts, including managers.
SELECT COUNT(*) AS "ActiveEmployees" FROM "Employees"
WHERE "Active" AND "EmailVerified" AND "ApprovalStatus"='Approved' AND "Role" IN ('manager','employee');
