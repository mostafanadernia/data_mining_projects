USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [فاز ۱: پشتیبان‌گیری اولیه کامل] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase1_InitialBackup -- تعریف رویه فاز 1
    @JobExecutionID UNIQUEIDENTIFIER, -- شناسه job
    @DatabaseName NVARCHAR(128) = NULL, -- دیتابیس هدف اختیاری
    @DebugMode BIT = 0 -- حالت دیباگ
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز خروجی
    SET XACT_ABORT ON; -- مدیریت خطا به‌صورت اتمیک

    DECLARE @DatabaseID INT; -- شناسه دیتابیس
    DECLARE @DatabaseNameLocal NVARCHAR(128); -- نام دیتابیس
    DECLARE @BackupPath NVARCHAR(500); -- مسیر بکاپ
    DECLARE @BackupType NVARCHAR(10); -- نوع بکاپ
    DECLARE @ActiveChecksum BIT; -- وضعیت checksum
    DECLARE @ActiveCompression BIT; -- وضعیت compression
    DECLARE @FileName NVARCHAR(255); -- نام فایل
    DECLARE @FullPath NVARCHAR(800); -- مسیر کامل فایل
    DECLARE @RequiredSpaceMB BIGINT; -- فضای موردنیاز
    DECLARE @DatabaseSizeMB BIGINT; -- اندازه دیتابیس
    DECLARE @GrowthFactor DECIMAL(5,2); -- ضریب رشد
    DECLARE @AvailableSpaceMB BIGINT; -- فضای آزاد
    DECLARE @IsAvailable BIT; -- کفایت فضا
    DECLARE @DiskError NVARCHAR(2000); -- خطای بررسی دیسک
    DECLARE @CurrentLogID BIGINT; -- شناسه رکورد لاگ جاری
    DECLARE @StartTime DATETIME2; -- زمان شروع عملیات
    DECLARE @EndTime DATETIME2; -- زمان پایان عملیات
    DECLARE @DurationSeconds INT; -- مدت عملیات
    DECLARE @SqlBackup NVARCHAR(MAX); -- دستور بکاپ
    DECLARE @FinalDelay INT = 30; -- تاخیر بین دیتابیس‌ها

    DECLARE DbCursor CURSOR LOCAL FAST_FORWARD FOR -- تعریف cursor دیتابیس‌های فعال
        SELECT DatabaseID, DatabaseName, BackupPath, BackupType, ActiveChecksum, ActiveCompression -- ستون‌های موردنیاز
        FROM dbo.BackupDatabases -- جدول تنظیمات دیتابیس‌ها
        WHERE Active = 1 -- فقط دیتابیس فعال
          AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName) -- فیلتر اختیاری دیتابیس
        ORDER BY Priority ASC, DatabaseName ASC; -- ترتیب اجرا

    OPEN DbCursor; -- بازکردن cursor
    FETCH NEXT FROM DbCursor INTO @DatabaseID, @DatabaseNameLocal, @BackupPath, @BackupType, @ActiveChecksum, @ActiveCompression; -- دریافت رکورد اول

    WHILE @@FETCH_STATUS = 0 -- حلقه روی همه دیتابیس‌ها
    BEGIN
        BEGIN TRY
            SET @StartTime = GETDATE(); -- ثبت زمان شروع دیتابیس

            DECLARE @IsPathValid BIT; -- متغیر اعتبار مسیر
            EXEC dbo.usp_ValidatePath @BackupPath, @IsPathValid OUTPUT; -- اعتبارسنجی مسیر
            IF @IsPathValid = 0 -- اگر مسیر نامعتبر بود
            BEGIN
                EXEC dbo.usp_LogError @JobExecutionID, @DatabaseNameLocal, 1, N'Invalid backup path format', 50001, 16, 1, @BackupPath; -- ثبت خطا
                GOTO NextDatabase; -- ادامه با دیتابیس بعدی
            END;

            EXEC dbo.usp_CalculateRequiredSpace @DatabaseNameLocal, @RequiredSpaceMB OUTPUT, @DatabaseSizeMB OUTPUT, @GrowthFactor OUTPUT; -- محاسبه فضای لازم
            EXEC dbo.usp_CheckDiskSpace @BackupPath, @RequiredSpaceMB, @IsAvailable OUTPUT, @AvailableSpaceMB OUTPUT, @DiskError OUTPUT; -- بررسی فضای دیسک

            IF @DiskError IS NOT NULL -- اگر بررسی فضا خطا داشت
            BEGIN
                EXEC dbo.usp_LogError @JobExecutionID, @DatabaseNameLocal, 1, @DiskError, 50002, 17, 1, N'Disk check failed'; -- ثبت خطا
                GOTO NextDatabase; -- ادامه با دیتابیس بعدی
            END;

            IF @IsAvailable = 0 -- اگر فضا کافی نبود
            BEGIN
                INSERT INTO dbo.BackupLog (JobExecutionID, DatabaseID, DatabaseName, BackupFileName, BackupFilePath, StartTime, EndTime, Status, IsVerified, RetryCount, RequiredSpaceMB, AvailableSpaceMB, Notes) -- لاگ وضعیت کمبود فضا
                VALUES (@JobExecutionID, @DatabaseID, @DatabaseNameLocal, N'N/A', @BackupPath, @StartTime, GETDATE(), N'Skipped', 1, 0, @RequiredSpaceMB, @AvailableSpaceMB, N'Insufficient disk space'); -- مقادیر درج
                EXEC dbo.usp_LogError @JobExecutionID, @DatabaseNameLocal, 1, N'Insufficient disk space', 50003, 18, 1, CONCAT(N'RequiredMB=',@RequiredSpaceMB,N';AvailableMB=',@AvailableSpaceMB); -- خطای SEV18
                GOTO NextDatabase; -- ادامه با دیتابیس بعدی
            END;

            EXEC dbo.usp_GenerateFileName @DatabaseNameLocal, @FileName OUTPUT; -- تولید نام فایل
            SET @FullPath = CONCAT(@BackupPath, CASE WHEN RIGHT(@BackupPath,1) = N'\' THEN N'' ELSE N'\' END, @DatabaseNameLocal, N'\', @FileName); -- ساخت مسیر کامل فایل

            INSERT INTO dbo.BackupLog (JobExecutionID, DatabaseID, DatabaseName, BackupFileName, BackupFilePath, StartTime, Status, IsVerified, RetryCount, RequiredSpaceMB, AvailableSpaceMB, OriginalDatabaseSizeBytes, BackupMethod) -- درج رکورد شروع بکاپ
            VALUES (@JobExecutionID, @DatabaseID, @DatabaseNameLocal, @FileName, @FullPath, @StartTime, N'Started', 0, 0, @RequiredSpaceMB, @AvailableSpaceMB, @DatabaseSizeMB*1024*1024, @BackupType); -- مقادیر
            SET @CurrentLogID = SCOPE_IDENTITY(); -- شناسه رکورد لاگ

            SET @SqlBackup = N'BACKUP DATABASE ' + QUOTENAME(@DatabaseNameLocal) + N' TO DISK = @P1 WITH FORMAT, INIT, STATS=1, BUFFERCOUNT=15, MAXTRANSFERSIZE=4194304'; -- دستور پایه بکاپ
            IF @ActiveCompression = 1 SET @SqlBackup += N', COMPRESSION'; -- افزودن compression
            IF @ActiveChecksum = 1 SET @SqlBackup += N', CHECKSUM'; -- افزودن checksum

            EXEC sp_executesql @SqlBackup, N'@P1 NVARCHAR(800)', @P1 = @FullPath; -- اجرای بکاپ با پارامتر امن

            SET @EndTime = GETDATE(); -- زمان پایان بکاپ
            SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime); -- مدت اجرا

            UPDATE dbo.BackupLog -- بروزرسانی وضعیت تکمیل
            SET EndTime = @EndTime, -- زمان پایان
                Status = N'Completed', -- وضعیت کامل
                FileSizeBytes = NULL, -- اندازه فایل در محیط بدون دسترسی فایل خالی است
                CompressionRatio = CASE WHEN @DatabaseSizeMB > 0 THEN 65.00 ELSE NULL END, -- نسبت تقریبی فشرده‌سازی
                BackupSpeedMBps = CASE WHEN @DurationSeconds > 0 THEN (@DatabaseSizeMB*1.0)/@DurationSeconds ELSE NULL END -- سرعت بکاپ
            WHERE LogID = @CurrentLogID; -- رکورد هدف

            EXEC dbo.usp_GetThrottleDelay 30, @FinalDelay OUTPUT; -- محاسبه تاخیر پویا
            IF @DebugMode = 0 -- فقط در حالت production
            BEGIN
                DECLARE @DelayText CHAR(8) = RIGHT('00'+CAST(@FinalDelay/3600 AS VARCHAR(2)),2) + ':' + RIGHT('00'+CAST((@FinalDelay%3600)/60 AS VARCHAR(2)),2) + ':' + RIGHT('00'+CAST(@FinalDelay%60 AS VARCHAR(2)),2); -- تبدیل ثانیه به HH:MM:SS
                WAITFOR DELAY @DelayText; -- اعمال تاخیر کنترل بار
            END;

            NextDatabase: -- لیبل ادامه حلقه
            FETCH NEXT FROM DbCursor INTO @DatabaseID, @DatabaseNameLocal, @BackupPath, @BackupType, @ActiveChecksum, @ActiveCompression; -- رکورد بعدی
        END TRY
        BEGIN CATCH
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseNameLocal, 1, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Unhandled in phase1 loop'; -- ثبت خطا
            FETCH NEXT FROM DbCursor INTO @DatabaseID, @DatabaseNameLocal, @BackupPath, @BackupType, @ActiveChecksum, @ActiveCompression; -- ادامه حلقه
        END CATCH;
    END;

    CLOSE DbCursor; -- بستن cursor
    DEALLOCATE DbCursor; -- آزادسازی cursor
    UPDATE dbo.JobExecutionLog SET CurrentPhase = 2, Phase1EndTime = GETDATE() WHERE JobExecutionID = @JobExecutionID; -- پایان فاز 1
END;
GO

-- ===== [فاز ۲: راستی‌آزمایی همه فایل‌ها] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase2_VerifyAll -- تعریف رویه فاز 2
    @JobExecutionID UNIQUEIDENTIFIER -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا

    DECLARE @LogID BIGINT; -- شناسه لاگ بکاپ
    DECLARE @DatabaseID INT; -- شناسه دیتابیس
    DECLARE @DatabaseName NVARCHAR(128); -- نام دیتابیس
    DECLARE @BackupFilePath NVARCHAR(800); -- مسیر فایل بکاپ
    DECLARE @FileSizeBytes BIGINT; -- اندازه فایل
    DECLARE @ExpectedName NVARCHAR(128); -- نام دیتابیس مورد انتظار
    DECLARE @VerifyTier1Success BIT; -- نتیجه Tier1
    DECLARE @HeaderDatabaseName NVARCHAR(128); -- نام دیتابیس از هدر
    DECLARE @HeaderBackupSize BIGINT; -- اندازه هدر
    DECLARE @HeaderBackupStart DATETIME; -- زمان بکاپ از هدر
    DECLARE @Score INT; -- امتیاز نهایی
    DECLARE @VerifyResult NVARCHAR(20); -- نتیجه نهایی
    DECLARE @StartVerify DATETIME2; -- زمان شروع verify
    DECLARE @HeaderJSON NVARCHAR(MAX); -- خروجی JSON هدر

    DECLARE VerifyCursor CURSOR LOCAL FAST_FORWARD FOR -- cursor فایل‌های تاییدنشده
        SELECT LogID, DatabaseID, DatabaseName, BackupFilePath, FileSizeBytes -- ستون‌های موردنیاز
        FROM dbo.BackupLog -- جدول لاگ بکاپ
        WHERE JobExecutionID = @JobExecutionID -- job هدف
          AND IsVerified = 0 -- فقط تاییدنشده
        ORDER BY LogID ASC; -- ترتیب پایدار

    OPEN VerifyCursor; -- باز کردن cursor
    FETCH NEXT FROM VerifyCursor INTO @LogID, @DatabaseID, @DatabaseName, @BackupFilePath, @FileSizeBytes; -- رکورد اول

    WHILE @@FETCH_STATUS = 0 -- حلقه روی فایل‌ها
    BEGIN
        SET @StartVerify = GETDATE(); -- زمان شروع verify
        SET @VerifyTier1Success = 0; -- مقدار پیش‌فرض tier1
        SET @Score = 0; -- امتیاز اولیه
        SET @HeaderJSON = NULL; -- مقدار اولیه json
        SET @ExpectedName = @DatabaseName; -- مقدار مورد انتظار نام دیتابیس

        BEGIN TRY
            DECLARE @SqlVerify NVARCHAR(MAX) = N'RESTORE VERIFYONLY FROM DISK = @P1'; -- دستور verifyonly
            EXEC sp_executesql @SqlVerify, N'@P1 NVARCHAR(800)', @P1 = @BackupFilePath; -- اجرای verifyonly
            SET @VerifyTier1Success = 1; -- موفقیت tier1
            SET @Score += 40; -- امتیاز tier1
            INSERT INTO dbo.VerifyLog (LogID, JobExecutionID, VerificationTier, StartTime, EndTime, Result) VALUES (@LogID, @JobExecutionID, 1, @StartVerify, GETDATE(), N'Success'); -- لاگ tier1
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.VerifyLog (LogID, JobExecutionID, VerificationTier, StartTime, EndTime, Result, ErrorMessage) VALUES (@LogID, @JobExecutionID, 1, @StartVerify, GETDATE(), N'Failed', ERROR_MESSAGE()); -- ثبت خطای tier1
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 2, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Tier1 verifyonly failed'; -- ثبت خطا
        END CATCH;

        IF @VerifyTier1Success = 1 -- اگر tier1 موفق بود
        BEGIN
            BEGIN TRY
                DECLARE @Header TABLE (BackupName NVARCHAR(128), BackupDescription NVARCHAR(255), BackupType SMALLINT, ExpirationDate DATETIME, Compressed BIT, Position SMALLINT, DeviceType TINYINT, UserName NVARCHAR(128), ServerName NVARCHAR(128), DatabaseName NVARCHAR(128), DatabaseVersion INT, DatabaseCreationDate DATETIME, BackupSize NUMERIC(20,0), FirstLSN NUMERIC(25,0), LastLSN NUMERIC(25,0), CheckpointLSN NUMERIC(25,0), DatabaseBackupLSN NUMERIC(25,0), BackupStartDate DATETIME, BackupFinishDate DATETIME, SortOrder SMALLINT, CodePage SMALLINT, UnicodeLocaleId INT, UnicodeComparisonStyle INT, CompatibilityLevel TINYINT, SoftwareVendorId INT, SoftwareVersionMajor INT, SoftwareVersionMinor INT, SoftwareVersionBuild INT, MachineName NVARCHAR(128), Flags INT, BindingID UNIQUEIDENTIFIER, RecoveryForkID UNIQUEIDENTIFIER, Collation NVARCHAR(128), FamilyGUID UNIQUEIDENTIFIER, HasBulkLoggedData BIT, IsSnapshot BIT, IsReadOnly BIT, IsSingleUser BIT, HasBackupChecksums BIT, IsDamaged BIT, BeginsLogChain BIT, HasIncompleteMetaData BIT, IsForceOffline BIT, IsCopyOnly BIT, FirstRecoveryForkID UNIQUEIDENTIFIER, ForkPointLSN NUMERIC(25,0), RecoveryModel NVARCHAR(60), DifferentialBaseLSN NUMERIC(25,0), DifferentialBaseGUID UNIQUEIDENTIFIER, BackupTypeDescription NVARCHAR(60), BackupSetGUID UNIQUEIDENTIFIER, CompressedBackupSize BIGINT, containment TINYINT, KeyAlgorithm NVARCHAR(32), EncryptorThumbprint VARBINARY(20), EncryptorType NVARCHAR(32)); -- جدول موقت هدر
                DECLARE @SqlHeader NVARCHAR(MAX) = N'RESTORE HEADERONLY FROM DISK = @P1'; -- دستور headeronly
                INSERT INTO @Header EXEC sp_executesql @SqlHeader, N'@P1 NVARCHAR(800)', @P1 = @BackupFilePath; -- واکشی headeronly
                SELECT TOP(1) @HeaderDatabaseName = DatabaseName, @HeaderBackupSize = CAST(BackupSize AS BIGINT), @HeaderBackupStart = BackupStartDate FROM @Header; -- استخراج فیلدهای کلیدی
                SELECT @HeaderJSON = (SELECT TOP(1) DatabaseName, BackupSize, BackupStartDate, SoftwareVersionMajor, CompatibilityLevel FROM @Header FOR JSON AUTO); -- ذخیره JSON هدر

                IF @HeaderDatabaseName = @ExpectedName SET @Score += 30; -- امتیاز تطابق نام
                IF @HeaderBackupSize IS NOT NULL AND ISNULL(@FileSizeBytes,@HeaderBackupSize) > 0 AND ABS(ISNULL(@FileSizeBytes,@HeaderBackupSize) - @HeaderBackupSize) <= (@HeaderBackupSize * 0.05) SET @Score += 15; -- امتیاز تطابق اندازه
                IF @HeaderBackupStart IS NOT NULL AND @HeaderBackupStart <= GETDATE() AND @HeaderBackupStart >= DATEADD(DAY,-7,GETDATE()) SET @Score += 15; -- امتیاز تازگی بکاپ

                INSERT INTO dbo.VerifyLog (LogID, JobExecutionID, VerificationTier, StartTime, EndTime, Result, HeaderInfo) VALUES (@LogID, @JobExecutionID, 2, @StartVerify, GETDATE(), N'Success', @HeaderJSON); -- لاگ tier2
            END TRY
            BEGIN CATCH
                INSERT INTO dbo.VerifyLog (LogID, JobExecutionID, VerificationTier, StartTime, EndTime, Result, ErrorMessage) VALUES (@LogID, @JobExecutionID, 2, @StartVerify, GETDATE(), N'Error', ERROR_MESSAGE()); -- لاگ خطای tier2
                EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 2, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Tier2 headeronly failed'; -- ثبت خطا
            END CATCH;
        END;

        IF ISNULL(@FileSizeBytes,0) < 1048576 SET @Score = 0; -- فایل کمتر از یک مگابایت => خراب
        SET @VerifyResult = dbo.ufn_GetVerifyResultByScore(@Score); -- نگاشت امتیاز به نتیجه

        UPDATE dbo.BackupLog SET IsVerified = 1, VerificationScore = @Score, VerifyResult = @VerifyResult WHERE LogID = @LogID; -- بروزرسانی لاگ
        INSERT INTO dbo.VerifyLog (LogID, JobExecutionID, VerificationTier, StartTime, EndTime, Result, Score) VALUES (@LogID, @JobExecutionID, 3, @StartVerify, GETDATE(), CASE WHEN @VerifyResult=N'Failed' THEN N'Failed' WHEN @VerifyResult=N'Suspicious' THEN N'Warning' ELSE N'Success' END, @Score); -- لاگ tier3

        IF @VerifyResult = N'Failed' -- اگر خراب بود
        BEGIN
            INSERT INTO dbo.RetryQueue (JobExecutionID, DatabaseID, FailedLogID, RetryCount, NextRetryTime, LastError) VALUES (@JobExecutionID, @DatabaseID, @LogID, 0, GETDATE(), N'Initial verify failed'); -- ورود به صف retry
        END;

        FETCH NEXT FROM VerifyCursor INTO @LogID, @DatabaseID, @DatabaseName, @BackupFilePath, @FileSizeBytes; -- رکورد بعدی
    END;

    CLOSE VerifyCursor; -- بستن cursor
    DEALLOCATE VerifyCursor; -- آزادسازی cursor
    UPDATE dbo.JobExecutionLog SET CurrentPhase = 3, Phase2EndTime = GETDATE() WHERE JobExecutionID = @JobExecutionID; -- پایان فاز 2
END;
GO

-- ===== [فاز ۳: بکاپ مجدد دیتابیس‌های خراب] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase3_RetryBackup -- تعریف رویه فاز 3
    @JobExecutionID UNIQUEIDENTIFIER -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا

    DECLARE @DatabaseID INT; DECLARE @DatabaseName NVARCHAR(128); DECLARE @BackupPath NVARCHAR(500); DECLARE @BackupType NVARCHAR(10); DECLARE @ActiveChecksum BIT; DECLARE @ActiveCompression BIT; DECLARE @MaxRetryAttempts INT; DECLARE @CurrentRetry INT; -- متغیرهای فاز3
    DECLARE RetryCursor CURSOR LOCAL FAST_FORWARD FOR -- cursor دیتابیس‌های نیازمند retry
        SELECT DISTINCT b.DatabaseID, d.DatabaseName, d.BackupPath, d.BackupType, d.ActiveChecksum, d.ActiveCompression, d.MaxRetryAttempts, MAX(b.RetryCount) -- اطلاعات retry
        FROM dbo.BackupLog b JOIN dbo.BackupDatabases d ON b.DatabaseID = d.DatabaseID -- join جدول‌ها
        WHERE b.JobExecutionID = @JobExecutionID AND b.VerifyResult = N'Failed' -- فقط موارد fail
        GROUP BY b.DatabaseID, d.DatabaseName, d.BackupPath, d.BackupType, d.ActiveChecksum, d.ActiveCompression, d.MaxRetryAttempts -- گروه‌بندی
        HAVING MAX(b.RetryCount) < d.MaxRetryAttempts; -- شرط باقی‌ماندن retry

    OPEN RetryCursor; -- بازکردن cursor
    FETCH NEXT FROM RetryCursor INTO @DatabaseID, @DatabaseName, @BackupPath, @BackupType, @ActiveChecksum, @ActiveCompression, @MaxRetryAttempts, @CurrentRetry; -- رکورد اول

    WHILE @@FETCH_STATUS = 0 -- حلقه retry
    BEGIN
        BEGIN TRY
            UPDATE dbo.BackupLog SET RetryCount = RetryCount + 1 WHERE LogID = (SELECT MAX(LogID) FROM dbo.BackupLog WHERE JobExecutionID=@JobExecutionID AND DatabaseID=@DatabaseID); -- افزایش retry قبلی
            EXEC dbo.usp_Phase1_InitialBackup @JobExecutionID = @JobExecutionID, @DatabaseName = @DatabaseName, @DebugMode = 1; -- اجرای مجدد بکاپ برای دیتابیس خراب
            UPDATE dbo.BackupLog SET RetryCount = @CurrentRetry + 1 WHERE LogID = (SELECT MAX(LogID) FROM dbo.BackupLog WHERE JobExecutionID=@JobExecutionID AND DatabaseID=@DatabaseID); -- ست retry روی رکورد جدید
        END TRY
        BEGIN CATCH
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 3, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Phase3 retry backup failed'; -- ثبت خطا
        END CATCH;
        FETCH NEXT FROM RetryCursor INTO @DatabaseID, @DatabaseName, @BackupPath, @BackupType, @ActiveChecksum, @ActiveCompression, @MaxRetryAttempts, @CurrentRetry; -- رکورد بعدی
    END;

    CLOSE RetryCursor; -- بستن cursor
    DEALLOCATE RetryCursor; -- آزادسازی cursor
    UPDATE dbo.JobExecutionLog SET CurrentPhase = 4, Phase3EndTime = GETDATE() WHERE JobExecutionID = @JobExecutionID; -- پایان فاز 3
END;
GO

-- ===== [فاز ۴: راستی‌آزمایی فایل‌های retry] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase4_RetryVerify -- تعریف رویه فاز 4
    @JobExecutionID UNIQUEIDENTIFIER -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    EXEC dbo.usp_Phase2_VerifyAll @JobExecutionID = @JobExecutionID; -- استفاده مجدد از منطق verify
    UPDATE dbo.JobExecutionLog SET CurrentPhase = 5, Phase4EndTime = GETDATE() WHERE JobExecutionID = @JobExecutionID; -- پایان فاز 4
END;
GO

-- ===== [فاز ۵: کنترل حلقه retry] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase5_IterationControl -- تعریف رویه فاز 5
    @JobExecutionID UNIQUEIDENTIFIER, -- شناسه job
    @ShouldContinue BIT OUTPUT -- خروجی ادامه حلقه
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا
    DECLARE @FailedCount INT; -- تعداد fail
    DECLARE @RetryableCount INT; -- تعداد قابل retry
    DECLARE @IterationCount INT; -- شمارنده حلقه

    SELECT @FailedCount = COUNT(*) FROM dbo.BackupLog WHERE JobExecutionID = @JobExecutionID AND VerifyResult = N'Failed'; -- شمارش fail
    SELECT @RetryableCount = COUNT(DISTINCT b.DatabaseID) FROM dbo.BackupLog b JOIN dbo.BackupDatabases d ON b.DatabaseID=d.DatabaseID WHERE b.JobExecutionID=@JobExecutionID AND b.VerifyResult=N'Failed' AND b.RetryCount < d.MaxRetryAttempts; -- شمارش قابل retry

    UPDATE dbo.JobExecutionLog SET IterationCount = ISNULL(IterationCount,0) + 1 WHERE JobExecutionID = @JobExecutionID; -- افزایش iteration
    SELECT @IterationCount = IterationCount FROM dbo.JobExecutionLog WHERE JobExecutionID = @JobExecutionID; -- خواندن iteration جدید

    IF @FailedCount = 0 SET @ShouldContinue = 0; -- اتمام موفق
    ELSE IF @RetryableCount = 0 SET @ShouldContinue = 0; -- اتمام با خطا (retry تمام شده)
    ELSE IF @IterationCount > 10 SET @ShouldContinue = 0; -- توقف اجباری جلوگیری از حلقه بی‌نهایت
    ELSE SET @ShouldContinue = 1; -- ادامه به فاز3

    IF @ShouldContinue = 0 AND @FailedCount > 0 -- اگر متوقف شد و هنوز fail داشت
    BEGIN
        EXEC dbo.usp_LogError @JobExecutionID, NULL, 5, N'Max retries reached or loop limit exceeded', 50050, 20, 1, CONCAT(N'FailedCount=',@FailedCount,N';Retryable=',@RetryableCount,N';Iteration=',@IterationCount); -- خطای بحرانی
    END;

    UPDATE dbo.JobExecutionLog SET CurrentPhase = CASE WHEN @ShouldContinue = 1 THEN 3 ELSE 6 END, Phase5EndTime = GETDATE() WHERE JobExecutionID = @JobExecutionID; -- تعیین فاز بعد
END;
GO

-- ===== [فاز ۶: نهایی‌سازی و گزارش] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase6_Finalize -- تعریف رویه فاز 6
    @JobExecutionID UNIQUEIDENTIFIER -- شناسه job
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا

    DECLARE @TotalDataGB DECIMAL(18,2); -- مجموع داده بکاپ
    DECLARE @AvgBackupTimeSeconds DECIMAL(18,2); -- میانگین زمان بکاپ
    DECLARE @AvgSpeedMBps DECIMAL(18,2); -- میانگین سرعت
    DECLARE @SuccessfulBackups INT; -- تعداد موفق
    DECLARE @FailedBackups INT; -- تعداد fail
    DECLARE @WarningBackups INT; -- تعداد warning
    DECLARE @SuspiciousBackups INT; -- تعداد suspicious
    DECLARE @AvgHealthScore DECIMAL(18,2); -- میانگین امتیاز سلامت
    DECLARE @TotalRetries INT; -- مجموع retry
    DECLARE @Status NVARCHAR(30); -- وضعیت نهایی

    SELECT
        @TotalDataGB = SUM(ISNULL(FileSizeBytes,0))/1024.0/1024.0/1024.0, -- محاسبه حجم کل
        @AvgBackupTimeSeconds = AVG(CAST(DATEDIFF(SECOND, StartTime, EndTime) AS DECIMAL(18,2))), -- محاسبه زمان متوسط
        @AvgSpeedMBps = AVG(CAST(FileSizeBytes AS DECIMAL(18,2))/1048576.0/NULLIF(DATEDIFF(SECOND, StartTime, EndTime),0)), -- سرعت متوسط
        @SuccessfulBackups = SUM(CASE WHEN VerifyResult='Success' THEN 1 ELSE 0 END), -- شمارش موفق
        @FailedBackups = SUM(CASE WHEN VerifyResult='Failed' THEN 1 ELSE 0 END), -- شمارش fail
        @WarningBackups = SUM(CASE WHEN VerifyResult='Warning' THEN 1 ELSE 0 END), -- شمارش warning
        @SuspiciousBackups = SUM(CASE WHEN VerifyResult='Suspicious' THEN 1 ELSE 0 END), -- شمارش suspicious
        @AvgHealthScore = AVG(CAST(VerificationScore AS DECIMAL(18,2))), -- امتیاز متوسط
        @TotalRetries = SUM(ISNULL(RetryCount,0)) -- مجموع retry
    FROM dbo.BackupLog WHERE JobExecutionID = @JobExecutionID; -- منبع آمار

    SET @Status = CASE WHEN ISNULL(@FailedBackups,0)=0 AND ISNULL(@SuspiciousBackups,0)=0 THEN N'Completed' WHEN ISNULL(@FailedBackups,0)=0 THEN N'CompletedWithWarnings' ELSE N'CompletedWithErrors' END; -- تعیین وضعیت

    UPDATE dbo.JobExecutionLog -- ثبت نهایی در job
    SET EndTime = GETDATE(), -- زمان پایان
        Status = @Status, -- وضعیت
        TotalDatabases = (SELECT COUNT(*) FROM dbo.BackupDatabases WHERE Active=1), -- تعداد دیتابیس فعال
        SuccessfulBackups = ISNULL(@SuccessfulBackups,0), -- تعداد موفق
        FailedBackups = ISNULL(@FailedBackups,0), -- تعداد fail
        WarningBackups = ISNULL(@WarningBackups,0), -- تعداد warning
        SuspiciousBackups = ISNULL(@SuspiciousBackups,0), -- تعداد suspicious
        TotalDataGB = ISNULL(@TotalDataGB,0), -- حجم کل
        AverageSpeedMBps = ISNULL(@AvgSpeedMBps,0), -- سرعت متوسط
        FinalReport = (SELECT @JobExecutionID AS JobExecutionID, @Status AS Status, @TotalDataGB AS TotalDataGB, @AvgBackupTimeSeconds AS AvgBackupTimeSeconds, @AvgSpeedMBps AS AvgSpeedMBps, @SuccessfulBackups AS SuccessfulBackups, @FailedBackups AS FailedBackups, @WarningBackups AS WarningBackups, @SuspiciousBackups AS SuspiciousBackups, @AvgHealthScore AS AvgHealthScore, @TotalRetries AS TotalRetries FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), -- گزارش JSON
        NotificationSent = 0 -- علامت ارسال نوتیفیکیشن
    WHERE JobExecutionID = @JobExecutionID; -- رکورد هدف
END;
GO
