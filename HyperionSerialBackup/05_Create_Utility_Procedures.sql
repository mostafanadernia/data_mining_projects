USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [رویه ثبت خطا] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_LogError -- تعریف رویه ثبت خطا
    @JobExecutionID UNIQUEIDENTIFIER = NULL, -- شناسه job
    @DatabaseName NVARCHAR(128) = NULL, -- نام دیتابیس
    @Phase INT, -- شماره فاز
    @ErrorMessage NVARCHAR(MAX), -- متن خطا
    @ErrorNumber INT, -- شماره خطا
    @Severity INT, -- شدت خطا
    @ErrorState INT = NULL -- وضعیت خطا
AS
BEGIN
    SET NOCOUNT ON; -- جلوگیری از پیام تعداد رکورد
    SET XACT_ABORT ON; -- شکست اتمیک تراکنش در خطا
    INSERT INTO dbo.ErrorLog (JobExecutionID, DatabaseName, Phase, ErrorMessage, ErrorNumber, ErrorSeverity, ErrorState) -- درج خطا
    VALUES (@JobExecutionID, @DatabaseName, @Phase, @ErrorMessage, @ErrorNumber, @Severity, @ErrorState); -- مقادیر
END;
GO

-- ===== [رویه اعتبارسنجی مسیر] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_ValidatePath -- تعریف رویه بررسی مسیر
    @Path NVARCHAR(500), -- مسیر ورودی
    @OUTPUT_IsValid BIT OUTPUT -- خروجی اعتبار
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    SET @OUTPUT_IsValid = dbo.ufn_IsValidBackupPath(@Path); -- فراخوانی تابع مسیر
END;
GO

-- ===== [رویه تولید نام فایل] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_GenerateFileName -- تعریف رویه نام‌گذاری فایل
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @OUTPUT_FileName NVARCHAR(255) OUTPUT -- نام فایل خروجی
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @Stamp NVARCHAR(15) = CONVERT(CHAR(8), GETDATE(), 112) + '-' + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', ''); -- تولید timestamp
    DECLARE @RRR NVARCHAR(3) = RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS NVARCHAR(3)),3); -- تولید عدد تصادفی 100-999
    SET @OUTPUT_FileName = CONCAT(@DatabaseName, '_', @Stamp, '_', @RRR, '_FU_001.bak'); -- ساخت نام نهایی فایل
END;
GO

-- ===== [رویه محاسبه فضای موردنیاز] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_CalculateRequiredSpace -- تعریف رویه محاسبه فضای لازم
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @OUTPUT_RequiredSpaceMB BIGINT OUTPUT, -- خروجی فضای لازم
    @OUTPUT_DatabaseSizeMB BIGINT OUTPUT -- خروجی اندازه دیتابیس
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @SizeMB DECIMAL(18,2); -- اندازه دیتابیس
    SELECT @SizeMB = SUM(size * 8.0 / 1024.0) FROM sys.master_files WHERE database_id = DB_ID(@DatabaseName); -- استخراج اندازه دیتابیس
    SET @OUTPUT_DatabaseSizeMB = CAST(ISNULL(@SizeMB,0) AS BIGINT); -- ست کردن خروجی اندازه
    SET @OUTPUT_RequiredSpaceMB = dbo.ufn_CalcRequiredSpaceMB(@SizeMB, 1.0); -- محاسبه فضای لازم
END;
GO

-- ===== [رویه آپدیت پیشرفت job] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_UpdateJobProgress
    @JobExecutionID UNIQUEIDENTIFIER,
    @Phase INT,
    @Status NVARCHAR(20),
    @AdditionalInfo NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    UPDATE dbo.JobExecutionLog SET CurrentPhase = @Phase, Status = @Status WHERE JobExecutionID = @JobExecutionID; -- ثبت وضعیت فعلی
    IF @AdditionalInfo IS NOT NULL INSERT INTO dbo.ErrorLog(JobExecutionID,DatabaseName,Phase,ErrorMessage,ErrorNumber,ErrorSeverity) VALUES(@JobExecutionID,NULL,@Phase,@AdditionalInfo,0,10); -- ثبت پیام اطلاعاتی
END;
GO
