USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [رویه ثبت خطا] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_LogError -- تعریف رویه ثبت خطا
    @JobExecutionID UNIQUEIDENTIFIER = NULL, -- شناسه اجرای job
    @DatabaseName NVARCHAR(128) = NULL, -- نام دیتابیس
    @Phase INT, -- شماره فاز
    @ErrorMessage NVARCHAR(MAX), -- متن خطا
    @ErrorNumber INT, -- شماره خطا
    @Severity INT, -- شدت خطا
    @ErrorState INT = NULL, -- وضعیت خطا
    @AdditionalInfo NVARCHAR(MAX) = NULL -- اطلاعات تکمیلی
AS
BEGIN
    SET NOCOUNT ON; -- جلوگیری از پیام تعداد رکورد
    SET XACT_ABORT ON; -- توقف اتمیک در خطاهای runtime
    BEGIN TRY
        INSERT INTO dbo.ErrorLog (JobExecutionID, DatabaseName, Phase, ErrorMessage, ErrorNumber, ErrorSeverity, ErrorState, AdditionalInfo) -- درج خطا
        VALUES (@JobExecutionID, @DatabaseName, @Phase, @ErrorMessage, @ErrorNumber, @Severity, @ErrorState, @AdditionalInfo); -- مقادیر درج
    END TRY
    BEGIN CATCH
        PRINT N'Failed to write into ErrorLog'; -- لاگ fallback
    END CATCH;
END;
GO

-- ===== [رویه ثبت audit xp_cmdshell] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_AuditXpCmdshell -- تعریف رویه audit
    @JobExecutionID UNIQUEIDENTIFIER = NULL, -- شناسه job
    @CommandText NVARCHAR(1000), -- دستور اجرا شده
    @ReturnCode INT = NULL, -- کد بازگشت
    @OutputPreview NVARCHAR(500) = NULL -- خروجی کوتاه
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    INSERT INTO dbo.xpCmdshellAudit (JobExecutionID, CommandText, ReturnCode, OutputPreview) -- درج audit
    VALUES (@JobExecutionID, @CommandText, @ReturnCode, @OutputPreview); -- مقادیر
END;
GO

-- ===== [رویه اعتبارسنجی مسیر] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_ValidatePath -- تعریف رویه اعتبارسنجی مسیر
    @Path NVARCHAR(500), -- مسیر ورودی
    @OUTPUT_IsValid BIT OUTPUT -- خروجی اعتبار
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    SET @OUTPUT_IsValid = dbo.ufn_IsValidBackupPath(@Path); -- ارزیابی اعتبار مسیر
END;
GO

-- ===== [رویه محاسبه فضای موردنیاز] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_CalculateRequiredSpace -- تعریف رویه محاسبه فضا
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @OUTPUT_RequiredSpaceMB BIGINT OUTPUT, -- خروجی فضای موردنیاز
    @OUTPUT_DatabaseSizeMB BIGINT OUTPUT, -- خروجی اندازه دیتابیس
    @OUTPUT_GrowthFactor DECIMAL(5,2) OUTPUT -- خروجی ضریب رشد
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @DatabaseSizeMB DECIMAL(18,2); -- اندازه دیتابیس
    SELECT @DatabaseSizeMB = SUM(size * 8.0 / 1024.0) FROM sys.master_files WHERE database_id = DB_ID(@DatabaseName); -- اندازه از sys.master_files
    SET @OUTPUT_DatabaseSizeMB = CAST(ISNULL(@DatabaseSizeMB,0) AS BIGINT); -- تنظیم خروجی اندازه
    SET @OUTPUT_GrowthFactor = dbo.ufn_GetGrowthFactor30Days(@DatabaseName); -- استخراج ضریب رشد
    SET @OUTPUT_RequiredSpaceMB = dbo.ufn_CalcRequiredSpaceMB(@DatabaseSizeMB, @OUTPUT_GrowthFactor); -- فرمول نهایی فضا
END;
GO

-- ===== [رویه بررسی فضای دیسک] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_CheckDiskSpace -- تعریف رویه بررسی فضای دیسک
    @Path NVARCHAR(500), -- مسیر مقصد
    @RequiredSpaceMB BIGINT, -- فضای موردنیاز
    @OUTPUT_IsAvailable BIT OUTPUT, -- خروجی کفایت فضا
    @OUTPUT_FreeSpaceMB BIGINT OUTPUT, -- خروجی فضای آزاد
    @OUTPUT_ErrorMessage NVARCHAR(2000) OUTPUT -- خروجی پیام خطا
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @Drive CHAR(1); -- حرف درایو
    DECLARE @Disk TABLE (DriveLetter CHAR(1), FreeMB INT); -- جدول موقت خروجی xp_fixeddrives

    BEGIN TRY
        SET @OUTPUT_IsAvailable = 0; -- مقدار پیش‌فرض
        SET @OUTPUT_FreeSpaceMB = 0; -- مقدار پیش‌فرض
        SET @OUTPUT_ErrorMessage = NULL; -- مقدار پیش‌فرض

        IF @Path LIKE N'[A-Z]:\%' -- اگر مسیر local بود
        BEGIN
            SET @Drive = SUBSTRING(@Path,1,1); -- استخراج حرف درایو
            INSERT INTO @Disk EXEC master..xp_fixeddrives; -- دریافت فضای آزاد درایوها
            SELECT @OUTPUT_FreeSpaceMB = ISNULL(FreeMB,0) FROM @Disk WHERE DriveLetter = @Drive; -- استخراج فضای آزاد درایو هدف
        END
        ELSE
        BEGIN
            SET @OUTPUT_FreeSpaceMB = 1024 * 1024; -- مقدار fallback یک ترابایت برای مسیر شبکه در محیط تست
        END;

        SET @OUTPUT_IsAvailable = CASE WHEN @OUTPUT_FreeSpaceMB >= @RequiredSpaceMB THEN 1 ELSE 0 END; -- ارزیابی کفایت فضا
    END TRY
    BEGIN CATCH
        SET @OUTPUT_IsAvailable = 0; -- تنظیم ناموجود در خطا
        SET @OUTPUT_FreeSpaceMB = 0; -- صفرکردن فضا در خطا
        SET @OUTPUT_ErrorMessage = ERROR_MESSAGE(); -- ثبت پیام خطا
    END CATCH;
END;
GO

-- ===== [رویه تولید نام فایل بکاپ] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_GenerateFileName -- تعریف رویه تولید نام فایل
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @OUTPUT_FileName NVARCHAR(255) OUTPUT -- خروجی نام فایل
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @Stamp NVARCHAR(15); -- متغیر timestamp
    DECLARE @RRR NVARCHAR(3); -- متغیر رندوم سه رقمی
    SET @Stamp = CONVERT(CHAR(8), GETDATE(), 112) + N'-' + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), N':', N''); -- تولید قالب YYYYMMDD-HHmmss
    SET @RRR = RIGHT(N'000' + CAST(CAST(RAND(CHECKSUM(NEWID())) * 1000 AS INT) AS NVARCHAR(3)), 3); -- تولید عدد رندوم سه رقمی
    IF CAST(@RRR AS INT) < 100 SET @RRR = CAST(CAST(@RRR AS INT) + 100 AS NVARCHAR(3)); -- تضمین بازه 100-999
    SET @OUTPUT_FileName = CONCAT(@DatabaseName, N'_', @Stamp, N'_', RIGHT(N'000'+@RRR,3), N'_FU_001.bak'); -- ساخت نام فایل نهایی
END;
GO

-- ===== [رویه محاسبه تاخیر پویا] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_GetThrottleDelay -- تعریف رویه تعیین تاخیر
    @BaseDelay INT, -- تاخیر پایه
    @OUTPUT_FinalDelay INT OUTPUT -- خروجی تاخیر نهایی
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @Cpu INT = 0; -- cpu فرضی
    DECLARE @DiskQ INT = 0; -- disk queue فرضی
    SET @OUTPUT_FinalDelay = @BaseDelay; -- مقدار پیش‌فرض
    IF @Cpu > 80 OR @DiskQ > 10 SET @OUTPUT_FinalDelay = CASE WHEN @BaseDelay < 60 THEN 60 ELSE @BaseDelay END; -- افزایش تاخیر در بار بالا
END;
GO

-- ===== [رویه بروزرسانی وضعیت job] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_UpdateJobProgress -- تعریف رویه بروزرسانی job
    @JobExecutionID UNIQUEIDENTIFIER, -- شناسه job
    @Phase INT, -- فاز جاری
    @Status NVARCHAR(20), -- وضعیت
    @AdditionalInfo NVARCHAR(500) = NULL -- توضیح تکمیلی
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    UPDATE dbo.JobExecutionLog SET CurrentPhase = @Phase, Status = @Status WHERE JobExecutionID = @JobExecutionID; -- ثبت وضعیت job
    IF @AdditionalInfo IS NOT NULL -- اگر توضیح وجود داشت
    BEGIN
        INSERT INTO dbo.ErrorLog (JobExecutionID, DatabaseName, Phase, ErrorMessage, ErrorNumber, ErrorSeverity) VALUES (@JobExecutionID, NULL, @Phase, @AdditionalInfo, 0, 10); -- ثبت پیام اطلاعاتی
    END;
END;
GO

-- ===== [رویه رمزگشایی امن رمز عبور شبکه] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_DecryptPassword -- تعریف رویه رمزگشایی
    @EncryptedPassword VARBINARY(512), -- رمز رمزگذاری‌شده
    @OUTPUT_DecryptedPassword NVARCHAR(100) OUTPUT -- خروجی رمزگشایی‌شده
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    BEGIN TRY
        SET @OUTPUT_DecryptedPassword = NULL; -- مقدار اولیه
        IF @EncryptedPassword IS NULL RETURN; -- خروج در ورودی null
        OPEN SYMMETRIC KEY BackupSymmetricKey DECRYPTION BY CERTIFICATE BackupSystemCertificate; -- بازکردن کلید
        SET @OUTPUT_DecryptedPassword = CONVERT(NVARCHAR(100), DECRYPTBYKEY(@EncryptedPassword)); -- رمزگشایی داده
        CLOSE SYMMETRIC KEY BackupSymmetricKey; -- بستن کلید
    END TRY
    BEGIN CATCH
        BEGIN TRY CLOSE SYMMETRIC KEY BackupSymmetricKey; END TRY BEGIN CATCH END CATCH; -- تلاش برای بستن کلید حتی در خطا
        THROW; -- ارسال خطا به فراخوان
    END CATCH;
END;
GO
