USE [BackupLogDB];
GO

-- بازسازی ایندکس‌های سنگین
ALTER INDEX ALL ON dbo.BackupLog REBUILD WITH (ONLINE = OFF);
ALTER INDEX ALL ON dbo.VerifyLog REBUILD WITH (ONLINE = OFF);
ALTER INDEX ALL ON dbo.ErrorLog REBUILD WITH (ONLINE = OFF);

-- بروزرسانی آمار
UPDATE STATISTICS dbo.BackupLog WITH FULLSCAN;
UPDATE STATISTICS dbo.VerifyLog WITH FULLSCAN;
UPDATE STATISTICS dbo.ErrorLog WITH FULLSCAN;

-- پاکسازی رکوردهای audit قدیمی (بیش از 365 روز)
DELETE FROM dbo.xpCmdshellAudit WHERE CommandTime < DATEADD(DAY,-365,GETDATE());
GO
