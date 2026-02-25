USE [BackupLogDB];
GO

-- TS001: اجرای عادی
EXEC dbo.usp_BackupController_Main @DebugMode = 1;

-- TS002: بررسی وجود retry برای دیتابیس خراب
SELECT DatabaseName, COUNT(*) AS BackupAttempts FROM dbo.BackupLog GROUP BY DatabaseName;

-- TS003: بررسی ثبت خطاها
SELECT TOP 100 * FROM dbo.ErrorLog ORDER BY ErrorTime DESC;

-- TS004: بررسی امتیازدهی verification
SELECT DatabaseName, VerificationScore, VerifyResult FROM dbo.BackupLog ORDER BY LogID DESC;

-- TS005: بررسی حداکثر retry
SELECT b.DatabaseName, MAX(l.RetryCount) AS MaxRetrySeen, b.MaxRetryAttempts FROM dbo.BackupLog l JOIN dbo.BackupDatabases b ON l.DatabaseID=b.DatabaseID GROUP BY b.DatabaseName,b.MaxRetryAttempts;

-- TS006: بررسی retention
SELECT TOP 100 * FROM dbo.DeleteOldLog ORDER BY DeleteTime DESC;

-- TS007: چند خطای همزمان
SELECT Phase, ErrorSeverity, COUNT(*) AS Cnt FROM dbo.ErrorLog GROUP BY Phase, ErrorSeverity;

-- TS008: پایش عملیات طولانی
SELECT * FROM dbo.JobExecutionLog WHERE Status='Running';

-- TS009: امنیت xp_cmdshell
SELECT TOP 100 * FROM dbo.xpCmdshellAudit ORDER BY CommandTime DESC;

-- TS010: مسیر مخرب
DECLARE @ok BIT; EXEC dbo.usp_ValidatePath N'D:\Backups; DELETE FROM sys.tables --', @ok OUTPUT; SELECT @ok AS IsValid;
GO
