USE [BackupLogDB]; -- انتخاب دیتابیس هدف برای ساخت جداول
GO -- پایان batch

-- ===== [جدول تنظیمات دیتابیس‌ها] ===== --
CREATE TABLE dbo.BackupDatabases ( -- ایجاد جدول تنظیمات هر دیتابیس
    DatabaseID INT IDENTITY(1,1) PRIMARY KEY, -- کلید اصلی شناسه دیتابیس
    ServerName NVARCHAR(128) NOT NULL CONSTRAINT DF_BackupDatabases_ServerName DEFAULT @@SERVERNAME, -- نام سرور
    DatabaseName NVARCHAR(128) NOT NULL UNIQUE, -- نام دیتابیس یکتا
    BackupPath NVARCHAR(500) NOT NULL, -- مسیر ذخیره بکاپ
    BackupType NVARCHAR(10) NOT NULL CHECK (BackupType IN ('Local','UNC','NetUse')), -- نوع مسیر بکاپ
    NetworkUsername NVARCHAR(100) NULL, -- نام کاربری شبکه
    NetworkPassword VARBINARY(512) NULL, -- رمز عبور رمزگذاری‌شده
    DriveLetter CHAR(1) NULL CHECK (DriveLetter LIKE '[A-Z]'), -- حرف درایو برای net use
    MinFilesToKeep INT NOT NULL CONSTRAINT DF_BackupDatabases_MinFilesToKeep DEFAULT 7 CHECK (MinFilesToKeep >= 1), -- حداقل فایل نگهداری
    Active BIT NOT NULL CONSTRAINT DF_BackupDatabases_Active DEFAULT 1, -- فعال بودن دیتابیس
    ActiveChecksum BIT NOT NULL CONSTRAINT DF_BackupDatabases_ActiveChecksum DEFAULT 1, -- فعال بودن checksum
    ActiveCompression BIT NOT NULL CONSTRAINT DF_BackupDatabases_ActiveCompression DEFAULT 1, -- فعال بودن compression
    MaxRetryAttempts INT NOT NULL CONSTRAINT DF_BackupDatabases_MaxRetryAttempts DEFAULT 5 CHECK (MaxRetryAttempts BETWEEN 1 AND 20), -- حداکثر retry
    Priority TINYINT NOT NULL CONSTRAINT DF_BackupDatabases_Priority DEFAULT 5 CHECK (Priority BETWEEN 1 AND 10), -- اولویت
    Notes NVARCHAR(500) NULL, -- یادداشت
    CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_BackupDatabases_CreatedDate DEFAULT GETDATE(), -- زمان ایجاد
    ModifiedDate DATETIME2 NOT NULL CONSTRAINT DF_BackupDatabases_ModifiedDate DEFAULT GETDATE() -- زمان اصلاح
); -- پایان تعریف جدول
GO -- پایان batch

-- ===== [جدول تنظیمات عمومی] ===== --
CREATE TABLE dbo.BackupSettings (SettingID INT IDENTITY(1,1) PRIMARY KEY, DefaultBackupPath NVARCHAR(500) NOT NULL DEFAULT N'D:\Backups', DefaultMinFilesToKeep INT NOT NULL DEFAULT 7, DefaultMaxRetry INT NOT NULL DEFAULT 5, GlobalThrottleDelay INT NOT NULL DEFAULT 30, EnableEmailNotification BIT NOT NULL DEFAULT 1, EmailRecipients NVARCHAR(1000) NULL, EnableSMSAlert BIT NOT NULL DEFAULT 0, SMSRecipients NVARCHAR(500) NULL, EnableTeamsNotification BIT NOT NULL DEFAULT 1, TeamsWebhookURL NVARCHAR(500) NULL, RetentionCleanupEnabled BIT NOT NULL DEFAULT 1, MaintenanceWindowStart TIME NOT NULL DEFAULT '22:00', MaintenanceWindowEnd TIME NOT NULL DEFAULT '06:00', CreatedDate DATETIME2 NOT NULL DEFAULT GETDATE(), ModifiedDate DATETIME2 NOT NULL DEFAULT GETDATE()); -- ایجاد جدول BackupSettings
GO

-- ===== [جدول اجرای Job] ===== --
CREATE TABLE dbo.JobExecutionLog (JobExecutionID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY, JobName NVARCHAR(100) NOT NULL DEFAULT N'Nightly_Full_Backup', StartTime DATETIME2 NOT NULL DEFAULT GETDATE(), Phase1EndTime DATETIME2 NULL, Phase2EndTime DATETIME2 NULL, Phase3EndTime DATETIME2 NULL, Phase4EndTime DATETIME2 NULL, Phase5EndTime DATETIME2 NULL, EndTime DATETIME2 NULL, Status NVARCHAR(40) NOT NULL DEFAULT N'Running', CurrentPhase INT NOT NULL DEFAULT 1, IterationCount INT NOT NULL DEFAULT 0, TotalDatabases INT NULL, SuccessfulBackups INT NOT NULL DEFAULT 0, FailedBackups INT NOT NULL DEFAULT 0, WarningBackups INT NOT NULL DEFAULT 0, SuspiciousBackups INT NOT NULL DEFAULT 0, TotalDataGB DECIMAL(12,2) NULL, AverageSpeedMBps DECIMAL(12,2) NULL, FinalReport NVARCHAR(MAX) NULL, NotificationSent BIT NOT NULL DEFAULT 0, NotificationTime DATETIME2 NULL); -- ایجاد جدول JobExecutionLog
GO

-- ===== [جدول لاگ بکاپ] ===== --
CREATE TABLE dbo.BackupLog (LogID BIGINT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NOT NULL, DatabaseID INT NOT NULL, ServerName NVARCHAR(128) NOT NULL DEFAULT @@SERVERNAME, DatabaseName NVARCHAR(128) NOT NULL, BackupFileName NVARCHAR(255) NOT NULL, BackupFilePath NVARCHAR(800) NOT NULL, FileSizeBytes BIGINT NULL, OriginalDatabaseSizeBytes BIGINT NULL, StartTime DATETIME2 NOT NULL, EndTime DATETIME2 NULL, DurationSeconds AS DATEDIFF(SECOND, StartTime, EndTime), Status NVARCHAR(20) NOT NULL DEFAULT N'Started', IsVerified BIT NOT NULL DEFAULT 0, VerificationScore TINYINT NULL, VerifyResult NVARCHAR(20) NULL CHECK (VerifyResult IN ('Success','Warning','Suspicious','Failed') OR VerifyResult IS NULL), RetryCount INT NOT NULL DEFAULT 0, RequiredSpaceMB BIGINT NULL, AvailableSpaceMB BIGINT NULL, CompressionRatio DECIMAL(5,2) NULL, BackupMethod NVARCHAR(20) NULL, BackupSpeedMBps DECIMAL(10,2) NULL, Notes NVARCHAR(500) NULL, CONSTRAINT FK_BackupLog_Job FOREIGN KEY (JobExecutionID) REFERENCES dbo.JobExecutionLog(JobExecutionID), CONSTRAINT FK_BackupLog_DB FOREIGN KEY (DatabaseID) REFERENCES dbo.BackupDatabases(DatabaseID)); -- ایجاد جدول BackupLog
GO

-- ===== [جداول لاگ تکمیلی] ===== --
CREATE TABLE dbo.VerifyLog (VerifyID BIGINT IDENTITY(1,1) PRIMARY KEY, LogID BIGINT NOT NULL, JobExecutionID UNIQUEIDENTIFIER NOT NULL, VerificationTier TINYINT NOT NULL CHECK (VerificationTier IN (1,2,3)), StartTime DATETIME2 NOT NULL, EndTime DATETIME2 NOT NULL, DurationSeconds AS DATEDIFF(SECOND, StartTime, EndTime), Result NVARCHAR(20) NOT NULL CHECK (Result IN ('Success','Failed','Warning','Error')), Score TINYINT NULL, ErrorMessage NVARCHAR(MAX) NULL, HeaderInfo NVARCHAR(MAX) NULL, ChecksumValue VARBINARY(64) NULL, CONSTRAINT FK_VerifyLog_Log FOREIGN KEY (LogID) REFERENCES dbo.BackupLog(LogID)); -- ایجاد جدول VerifyLog
GO
CREATE TABLE dbo.DeleteOldLog (DeleteID BIGINT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NOT NULL, DatabaseID INT NOT NULL, FileName NVARCHAR(255) NOT NULL, FilePath NVARCHAR(500) NOT NULL, FileSizeBytes BIGINT NOT NULL, DeleteTime DATETIME2 NOT NULL DEFAULT GETDATE(), DeletionReason NVARCHAR(50) NOT NULL DEFAULT N'Retention Policy', VerificationStatusAtDeletion NVARCHAR(20) NULL, CONSTRAINT FK_DeleteOldLog_DB FOREIGN KEY (DatabaseID) REFERENCES dbo.BackupDatabases(DatabaseID)); -- ایجاد جدول حذف فایل‌های قدیمی
GO
CREATE TABLE dbo.DeleteBadLog (DeleteID BIGINT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NOT NULL, LogID BIGINT NOT NULL, FileName NVARCHAR(255) NOT NULL, FilePath NVARCHAR(500) NOT NULL, FileSizeBytes BIGINT NULL, DeleteTime DATETIME2 NOT NULL DEFAULT GETDATE(), Reason NVARCHAR(200) NOT NULL, VerificationScore TINYINT NULL, CONSTRAINT FK_DeleteBadLog_Log FOREIGN KEY (LogID) REFERENCES dbo.BackupLog(LogID)); -- ایجاد جدول حذف فایل‌های خراب
GO
CREATE TABLE dbo.ErrorLog (ErrorID BIGINT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NULL, DatabaseName NVARCHAR(128) NULL, Phase INT NOT NULL, ErrorTime DATETIME2 NOT NULL DEFAULT GETDATE(), ErrorMessage NVARCHAR(MAX) NOT NULL, ErrorNumber INT NOT NULL, ErrorSeverity INT NOT NULL CHECK (ErrorSeverity BETWEEN 1 AND 25), ErrorState INT NULL, AdditionalInfo NVARCHAR(MAX) NULL, IsResolved BIT NOT NULL DEFAULT 0, ResolutionNotes NVARCHAR(MAX) NULL, ResolvedBy NVARCHAR(128) NULL, ResolvedTime DATETIME2 NULL); -- ایجاد جدول ErrorLog
GO
CREATE TABLE dbo.RetryQueue (QueueID INT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NOT NULL, DatabaseID INT NOT NULL, FailedLogID BIGINT NOT NULL, RetryCount INT NOT NULL, NextRetryTime DATETIME2 NOT NULL, LastError NVARCHAR(MAX) NULL, CreatedDate DATETIME2 NOT NULL DEFAULT GETDATE(), ProcessedDate DATETIME2 NULL, CONSTRAINT FK_RetryQueue_DB FOREIGN KEY (DatabaseID) REFERENCES dbo.BackupDatabases(DatabaseID), CONSTRAINT FK_RetryQueue_Log FOREIGN KEY (FailedLogID) REFERENCES dbo.BackupLog(LogID)); -- ایجاد جدول RetryQueue
GO
CREATE TABLE dbo.DiskSpaceHistory (HistoryID BIGINT IDENTITY(1,1) PRIMARY KEY, DatabaseID INT NOT NULL, BackupPath NVARCHAR(500) NOT NULL, CheckTime DATETIME2 NOT NULL DEFAULT GETDATE(), TotalSpaceGB DECIMAL(10,2) NOT NULL, FreeSpaceGB DECIMAL(10,2) NOT NULL, UsedSpaceGB AS (TotalSpaceGB - FreeSpaceGB), FreePercentage AS (FreeSpaceGB * 100.0 / NULLIF(TotalSpaceGB,0)), DatabaseSizeGB DECIMAL(10,2) NOT NULL, RequiredSpaceGB DECIMAL(10,2) NOT NULL, IsSufficient BIT NOT NULL, DailyGrowthRateGB DECIMAL(10,2) NULL, PredictedFullDays INT NULL, CONSTRAINT FK_DiskSpaceHistory_DB FOREIGN KEY (DatabaseID) REFERENCES dbo.BackupDatabases(DatabaseID)); -- ایجاد جدول DiskSpaceHistory
GO
CREATE TABLE dbo.xpCmdshellAudit (AuditID BIGINT IDENTITY(1,1) PRIMARY KEY, JobExecutionID UNIQUEIDENTIFIER NULL, CommandTime DATETIME2 NOT NULL DEFAULT GETDATE(), CommandText NVARCHAR(1000) NOT NULL, ReturnCode INT NULL, OutputPreview NVARCHAR(500) NULL, ExecutedBy NVARCHAR(128) NOT NULL DEFAULT SYSTEM_USER, DatabaseContext NVARCHAR(128) NOT NULL DEFAULT DB_NAME()); -- ایجاد جدول Audit دستورات
GO

-- ===== [ایندکس‌های بهینه‌سازی] ===== --
CREATE INDEX IX_BackupDatabases_Active ON dbo.BackupDatabases(Active) WHERE Active = 1; -- ایندکس دیتابیس‌های فعال
CREATE INDEX IX_BackupDatabases_Priority ON dbo.BackupDatabases(Priority); -- ایندکس اولویت
CREATE INDEX IX_JobExecutionLog_Status ON dbo.JobExecutionLog(Status); -- ایندکس وضعیت job
CREATE INDEX IX_JobExecutionLog_StartTime ON dbo.JobExecutionLog(StartTime DESC); -- ایندکس زمان شروع
CREATE INDEX IX_BackupLog_JobExecutionID ON dbo.BackupLog(JobExecutionID); -- ایندکس کلید job
CREATE INDEX IX_BackupLog_IsVerified ON dbo.BackupLog(IsVerified) WHERE IsVerified = 0; -- ایندکس فایل‌های تاییدنشده
CREATE INDEX IX_BackupLog_VerifyResult ON dbo.BackupLog(VerifyResult); -- ایندکس نتیجه راستی‌آزمایی
CREATE INDEX IX_BackupLog_DatabaseID ON dbo.BackupLog(DatabaseID); -- ایندکس دیتابیس
CREATE INDEX IX_VerifyLog_LogID ON dbo.VerifyLog(LogID); -- ایندکس لاگ راستی‌آزمایی
CREATE INDEX IX_ErrorLog_Severity ON dbo.ErrorLog(ErrorSeverity); -- ایندکس شدت خطا
CREATE INDEX IX_RetryQueue_NextRetryTime ON dbo.RetryQueue(NextRetryTime) WHERE ProcessedDate IS NULL; -- ایندکس زمان retry
