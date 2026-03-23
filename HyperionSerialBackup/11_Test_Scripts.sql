USE [BackupLogDB]; -- انتخاب دیتابیس تست
GO -- پایان batch

-- ===== [TS001: اجرای عادی] ===== --
EXEC dbo.usp_BackupController_Main @DatabaseName = NULL, @ForceRestart = 1, @DebugMode = 1; -- اجرای کامل کنترلر در حالت دیباگ

-- ===== [TS002: بازیابی دیتابیس خراب با retry] ===== --
SELECT DatabaseName, COUNT(*) AS BackupAttempts, MAX(RetryCount) AS MaxRetryCount FROM dbo.BackupLog GROUP BY DatabaseName ORDER BY DatabaseName; -- بررسی تعداد تلاش‌ها

-- ===== [TS003: رخداد قطعی شبکه و خطاها] ===== --
SELECT TOP(200) ErrorTime, DatabaseName, Phase, ErrorSeverity, ErrorMessage FROM dbo.ErrorLog ORDER BY ErrorTime DESC; -- مشاهده خطاهای ثبت‌شده

-- ===== [TS004: کمبود فضای دیسک] ===== --
SELECT TOP(200) DatabaseName, RequiredSpaceMB, AvailableSpaceMB, Status, Notes FROM dbo.BackupLog WHERE Status IN (N'Skipped',N'Failed') ORDER BY LogID DESC; -- بررسی skip ناشی از کمبود فضا

-- ===== [TS005: عبور از سقف retry] ===== --
SELECT d.DatabaseName, d.MaxRetryAttempts, MAX(b.RetryCount) AS SeenRetry, SUM(CASE WHEN b.VerifyResult='Failed' THEN 1 ELSE 0 END) AS FailedEntries FROM dbo.BackupDatabases d LEFT JOIN dbo.BackupLog b ON d.DatabaseID=b.DatabaseID GROUP BY d.DatabaseName, d.MaxRetryAttempts ORDER BY d.DatabaseName; -- تحلیل retry

-- ===== [TS006: سیاست نگهداری فایل] ===== --
SELECT TOP(200) DatabaseID, FileName, DeletionReason, DeleteTime FROM dbo.DeleteOldLog ORDER BY DeleteTime DESC; -- گزارش حذف فایل‌های قدیمی

-- ===== [TS007: خطاهای همزمان] ===== --
SELECT Phase, ErrorSeverity, COUNT(*) AS Cnt FROM dbo.ErrorLog GROUP BY Phase, ErrorSeverity ORDER BY Phase, ErrorSeverity; -- توزیع خطا بر اساس فاز و شدت

-- ===== [TS008: عملیات طولانی و resume] ===== --
SELECT TOP(50) JobExecutionID, StartTime, EndTime, Status, CurrentPhase, IterationCount FROM dbo.JobExecutionLog ORDER BY StartTime DESC; -- مشاهده resume/phase progression

-- ===== [TS009: امنیت xp_cmdshell] ===== --
SELECT TOP(200) CommandTime, CommandText, ReturnCode, OutputPreview FROM dbo.xpCmdshellAudit ORDER BY CommandTime DESC; -- بررسی audit دستورات سیستم

-- ===== [TS010: جلوگیری از تزریق مسیر] ===== --
DECLARE @Output_IsValid BIT; -- تعریف خروجی اعتبار
EXEC dbo.usp_ValidatePath N'D:\Backups; DELETE FROM sys.tables --', @Output_IsValid OUTPUT; -- تست مسیر مخرب
SELECT @Output_IsValid AS IsValid; -- انتظار 0
GO -- پایان batch
