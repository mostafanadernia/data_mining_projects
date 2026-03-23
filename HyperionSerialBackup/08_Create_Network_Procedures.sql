USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [رویه فعال‌سازی کنترل‌شده xp_cmdshell] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Enable_xpCmdshell -- تعریف رویه فعال‌سازی xp_cmdshell
    @JobExecutionID UNIQUEIDENTIFIER = NULL -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    EXEC sp_configure 'show advanced options', 1; -- فعال‌سازی advanced options
    RECONFIGURE; -- اعمال تنظیمات
    EXEC sp_configure 'xp_cmdshell', 1; -- فعال‌سازی xp_cmdshell
    RECONFIGURE; -- اعمال تنظیمات
    EXEC dbo.usp_AuditXpCmdshell @JobExecutionID, N'Enable xp_cmdshell', 0, N'Enabled'; -- لاگ audit
END;
GO -- پایان batch

-- ===== [رویه غیرفعال‌سازی کنترل‌شده xp_cmdshell] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Disable_xpCmdshell -- تعریف رویه غیرفعال‌سازی xp_cmdshell
    @JobExecutionID UNIQUEIDENTIFIER = NULL -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    EXEC sp_configure 'xp_cmdshell', 0; -- غیرفعال‌سازی xp_cmdshell
    RECONFIGURE; -- اعمال تنظیمات
    EXEC dbo.usp_AuditXpCmdshell @JobExecutionID, N'Disable xp_cmdshell', 0, N'Disabled'; -- لاگ audit
END;
GO -- پایان batch

-- ===== [رویه اجرای امن xp_cmdshell با whitelist] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_ExecuteWhitelistedCmd -- تعریف رویه اجرای امن دستورات سیستم
    @JobExecutionID UNIQUEIDENTIFIER = NULL, -- شناسه job
    @CommandText NVARCHAR(1000), -- متن دستور
    @OUTPUT_ReturnCode INT OUTPUT -- خروجی کد بازگشت
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @CmdLower NVARCHAR(1000) = LOWER(LTRIM(RTRIM(@CommandText))); -- نرمال‌سازی دستور

    IF NOT (
        @CmdLower LIKE N'mkdir %' OR -- دستور مجاز mkdir
        @CmdLower LIKE N'del %' OR -- دستور مجاز del
        @CmdLower LIKE N'dir %' OR -- دستور مجاز dir
        @CmdLower LIKE N'net use %' OR -- دستور مجاز net use
        @CmdLower LIKE N'powershell -command %' OR -- دستور مجاز powershell
        @CmdLower LIKE N'wmic %' -- دستور مجاز wmic
    )
    BEGIN
        SET @OUTPUT_ReturnCode = -1; -- کد خطای عدم مجوز
        EXEC dbo.usp_AuditXpCmdshell @JobExecutionID, @CommandText, @OUTPUT_ReturnCode, N'Rejected by whitelist'; -- لاگ رد دستور
        THROW 51001, N'Command rejected by whitelist', 1; -- پرتاب خطای امنیتی
    END;

    EXEC @OUTPUT_ReturnCode = xp_cmdshell @CommandText, NO_OUTPUT; -- اجرای دستور سیستم
    EXEC dbo.usp_AuditXpCmdshell @JobExecutionID, @CommandText, @OUTPUT_ReturnCode, N'Executed'; -- لاگ اجرای دستور
END;
GO -- پایان batch

-- ===== [رویه پشتیبان‌گیری UNC] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_UNC -- تعریف رویه بکاپ UNC
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @BackupPath NVARCHAR(500), -- مسیر بکاپ
    @FileName NVARCHAR(255), -- نام فایل
    @UseChecksum BIT, -- فعال بودن checksum
    @UseCompression BIT, -- فعال بودن compression
    @Success BIT OUTPUT, -- خروجی موفقیت
    @FileSize BIGINT OUTPUT, -- خروجی اندازه فایل
    @ErrorMessage NVARCHAR(2000) OUTPUT -- خروجی خطا
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    BEGIN TRY
        DECLARE @FullPath NVARCHAR(800) = CONCAT(@BackupPath, CASE WHEN RIGHT(@BackupPath,1)=N'\' THEN N'' ELSE N'\' END, @DatabaseName, N'\', @FileName); -- مسیر کامل
        DECLARE @SqlBackup NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(@DatabaseName) + N' TO DISK = @P1 WITH FORMAT, INIT, STATS=1, BUFFERCOUNT=15, MAXTRANSFERSIZE=4194304'; -- دستور پایه
        IF @UseCompression = 1 SET @SqlBackup += N', COMPRESSION'; -- افزودن compression
        IF @UseChecksum = 1 SET @SqlBackup += N', CHECKSUM'; -- افزودن checksum
        EXEC sp_executesql @SqlBackup, N'@P1 NVARCHAR(800)', @P1 = @FullPath; -- اجرای بکاپ
        SET @Success = 1; -- ثبت موفقیت
        SET @FileSize = NULL; -- اندازه فایل در این محیط نامشخص
        SET @ErrorMessage = NULL; -- بدون خطا
    END TRY
    BEGIN CATCH
        SET @Success = 0; -- ثبت شکست
        SET @FileSize = NULL; -- اندازه نامشخص
        SET @ErrorMessage = ERROR_MESSAGE(); -- پیام خطا
    END CATCH;
END;
GO -- پایان batch

-- ===== [رویه پشتیبان‌گیری با net use] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_NetUse -- تعریف رویه بکاپ NetUse
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @UNCPath NVARCHAR(500), -- مسیر UNC
    @DriveLetter CHAR(1), -- حرف درایو موقت
    @Username NVARCHAR(100), -- نام کاربری شبکه
    @EncryptedPassword VARBINARY(512), -- رمز رمزگذاری‌شده
    @FileName NVARCHAR(255), -- نام فایل
    @UseChecksum BIT, -- فعال بودن checksum
    @UseCompression BIT, -- فعال بودن compression
    @Success BIT OUTPUT, -- خروجی موفقیت
    @FileSize BIGINT OUTPUT, -- خروجی اندازه فایل
    @ErrorMessage NVARCHAR(2000) OUTPUT -- خروجی خطا
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @DecryptedPassword NVARCHAR(100); -- متغیر رمزگشایی‌شده
    EXEC dbo.usp_DecryptPassword @EncryptedPassword, @DecryptedPassword OUTPUT; -- رمزگشایی رمز عبور
    DECLARE @Cmd NVARCHAR(1000); -- فرمان cmd
    DECLARE @ReturnCode INT; -- کد بازگشت
    DECLARE @Retry INT = 0; -- شمارنده retry
    SET @Success = 0; -- مقدار پیش‌فرض شکست

    BEGIN TRY
        EXEC dbo.usp_Enable_xpCmdshell NULL; -- فعال‌سازی کنترل‌شده xp_cmdshell
        WHILE @Retry < 3 AND @Success = 0 -- حداکثر سه بار تلاش map
        BEGIN
            SET @Cmd = CONCAT(N'net use ', @DriveLetter, N': ', @UNCPath, N' /user:', @Username, N' ', @DecryptedPassword); -- فرمان map
            EXEC dbo.usp_ExecuteWhitelistedCmd NULL, @Cmd, @ReturnCode OUTPUT; -- اجرای امن فرمان
            IF @ReturnCode = 0 -- اگر map موفق شد
            BEGIN
                EXEC dbo.usp_Backup_UNC @DatabaseName, CONCAT(@DriveLetter, N':'), @FileName, @UseChecksum, @UseCompression, @Success OUTPUT, @FileSize OUTPUT, @ErrorMessage OUTPUT; -- اجرای بکاپ روی درایو map
            END
            ELSE
            BEGIN
                SET @Retry += 1; -- افزایش retry
                WAITFOR DELAY '00:00:10'; -- تاخیر 10 ثانیه بین تلاش‌ها
            END;
        END;
    END TRY
    BEGIN CATCH
        SET @Success = 0; -- شکست عملیات
        SET @ErrorMessage = ERROR_MESSAGE(); -- ثبت خطا
    END CATCH
    BEGIN TRY
        SET @Cmd = CONCAT(N'net use ', @DriveLetter, N': /delete'); -- فرمان unmap
        EXEC dbo.usp_ExecuteWhitelistedCmd NULL, @Cmd, @ReturnCode OUTPUT; -- اجرای unmap
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_LogError NULL, @DatabaseName, 1, ERROR_MESSAGE(), ERROR_NUMBER(), 16, ERROR_STATE(), N'Failed to unmap drive'; -- ثبت خطای unmap
    END CATCH;
    EXEC dbo.usp_Disable_xpCmdshell NULL; -- غیرفعال‌سازی xp_cmdshell حتی در خطا
END;
GO -- پایان batch

-- ===== [رویه پشتیبان‌گیری با xp_cmdshell برای عملیات فایل] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_xpCmdshell -- تعریف رویه بکاپ xp_cmdshell
    @DatabaseName NVARCHAR(128), -- نام دیتابیس
    @BackupPath NVARCHAR(500), -- مسیر بکاپ
    @FileName NVARCHAR(255), -- نام فایل
    @UseChecksum BIT, -- فعال بودن checksum
    @UseCompression BIT, -- فعال بودن compression
    @Success BIT OUTPUT, -- خروجی موفقیت
    @FileSize BIGINT OUTPUT, -- خروجی اندازه فایل
    @ErrorMessage NVARCHAR(2000) OUTPUT -- خروجی خطا
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @Cmd NVARCHAR(1000); -- فرمان cmd
    DECLARE @ReturnCode INT; -- کد بازگشت
    BEGIN TRY
        EXEC dbo.usp_Enable_xpCmdshell NULL; -- فعال‌سازی xp_cmdshell
        SET @Cmd = CONCAT(N'mkdir "', @BackupPath, CASE WHEN RIGHT(@BackupPath,1)=N'\' THEN N'' ELSE N'\' END, @DatabaseName, N'"'); -- فرمان ساخت پوشه
        EXEC dbo.usp_ExecuteWhitelistedCmd NULL, @Cmd, @ReturnCode OUTPUT; -- اجرای امن ساخت پوشه
        EXEC dbo.usp_Backup_UNC @DatabaseName, @BackupPath, @FileName, @UseChecksum, @UseCompression, @Success OUTPUT, @FileSize OUTPUT, @ErrorMessage OUTPUT; -- اجرای بکاپ
    END TRY
    BEGIN CATCH
        SET @Success = 0; -- شکست عملیات
        SET @FileSize = NULL; -- اندازه نامشخص
        SET @ErrorMessage = ERROR_MESSAGE(); -- پیام خطا
    END CATCH;
    EXEC dbo.usp_Disable_xpCmdshell NULL; -- غیرفعال‌سازی xp_cmdshell حتی در خطا
END;
GO -- پایان batch
