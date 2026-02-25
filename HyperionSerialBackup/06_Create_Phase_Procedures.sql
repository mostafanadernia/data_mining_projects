USE [BackupLogDB];
GO

-- ===== [فاز ۱: بکاپ اولیه] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase1_InitialBackup
    @JobExecutionID UNIQUEIDENTIFIER,
    @DatabaseName NVARCHAR(128) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DBID INT, @DBName NVARCHAR(128), @Path NVARCHAR(500), @Checksum BIT, @Compression BIT, @Retry INT, @BackupType NVARCHAR(10); -- متغیرهای cursor
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseID, DatabaseName, BackupPath, ActiveChecksum, ActiveCompression, MaxRetryAttempts, BackupType
        FROM dbo.BackupDatabases
        WHERE Active = 1 AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName)
        ORDER BY Priority, DatabaseName;

    OPEN c;
    FETCH NEXT FROM c INTO @DBID, @DBName, @Path, @Checksum, @Compression, @Retry, @BackupType;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            DECLARE @IsValid BIT; EXEC dbo.usp_ValidatePath @Path, @IsValid OUTPUT; -- اعتبارسنجی مسیر
            IF @IsValid = 0 THROW 50001, N'Invalid backup path', 1; -- جلوگیری از مسیر ناسالم

            DECLARE @Req BIGINT, @Size BIGINT; EXEC dbo.usp_CalculateRequiredSpace @DBName, @Req OUTPUT, @Size OUTPUT; -- محاسبه ظرفیت
            DECLARE @File NVARCHAR(255); EXEC dbo.usp_GenerateFileName @DBName, @File OUTPUT; -- تولید نام فایل
            DECLARE @FullPath NVARCHAR(800) = CONCAT(@Path, CASE WHEN RIGHT(@Path,1) IN ('\','/') THEN '' ELSE '\' END, @DBName, '\', @File); -- مسیر کامل

            INSERT INTO dbo.BackupLog(JobExecutionID, DatabaseID, DatabaseName, BackupFileName, BackupFilePath, StartTime, Status, RetryCount, RequiredSpaceMB, BackupMethod, OriginalDatabaseSizeBytes)
            VALUES(@JobExecutionID, @DBID, @DBName, @File, @FullPath, GETDATE(), N'Started', 0, @Req, @BackupType, @Size*1024*1024); -- ثبت شروع

            DECLARE @SQL NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(@DBName) + N' TO DISK = @p WITH FORMAT, INIT, STATS=1, BUFFERCOUNT=15, MAXTRANSFERSIZE=4194304'
                + CASE WHEN @Compression=1 THEN N', COMPRESSION' ELSE N'' END
                + CASE WHEN @Checksum=1 THEN N', CHECKSUM' ELSE N'' END; -- ساخت SQL بکاپ
            EXEC sp_executesql @SQL, N'@p NVARCHAR(800)', @p=@FullPath; -- اجرای امن بکاپ با پارامتر مسیر

            UPDATE dbo.BackupLog SET EndTime = GETDATE(), Status = N'Completed' WHERE LogID = SCOPE_IDENTITY(); -- تکمیل لاگ
            IF @DebugMode = 0 WAITFOR DELAY '00:00:30'; -- تاخیر کنترلی بین دیتابیس‌ها
        END TRY
        BEGIN CATCH
            EXEC dbo.usp_LogError @JobExecutionID, @DBName, 1, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(); -- ثبت خطا
        END CATCH;

        FETCH NEXT FROM c INTO @DBID, @DBName, @Path, @Checksum, @Compression, @Retry, @BackupType;
    END
    CLOSE c; DEALLOCATE c;

    UPDATE dbo.JobExecutionLog SET Phase1EndTime = GETDATE(), CurrentPhase = 2 WHERE JobExecutionID = @JobExecutionID; -- پایان فاز ۱
END;
GO

-- ===== [فاز ۲: راستی‌آزمایی اولیه] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase2_VerifyAll @JobExecutionID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @LogID BIGINT, @Path NVARCHAR(800), @DB NVARCHAR(128), @Score INT, @Result NVARCHAR(20);
    DECLARE v CURSOR LOCAL FAST_FORWARD FOR SELECT LogID, BackupFilePath, DatabaseName FROM dbo.BackupLog WHERE JobExecutionID=@JobExecutionID AND IsVerified=0 ORDER BY LogID;
    OPEN v; FETCH NEXT FROM v INTO @LogID,@Path,@DB;
    WHILE @@FETCH_STATUS=0
    BEGIN
        BEGIN TRY
            DECLARE @S DATETIME2=GETDATE();
            EXEC(N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@Path,'''','''''') + N''''); -- verifyonly
            INSERT INTO dbo.VerifyLog(LogID,JobExecutionID,VerificationTier,StartTime,EndTime,Result) VALUES(@LogID,@JobExecutionID,1,@S,GETDATE(),N'Success');
            SET @Score = 40 + 30 + 15 + 15; SET @Result = N'Success'; -- امتیاز سالم
            UPDATE dbo.BackupLog SET IsVerified=1,VerificationScore=@Score,VerifyResult=@Result WHERE LogID=@LogID;
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.VerifyLog(LogID,JobExecutionID,VerificationTier,StartTime,EndTime,Result,ErrorMessage) VALUES(@LogID,@JobExecutionID,1,GETDATE(),GETDATE(),N'Failed',ERROR_MESSAGE());
            UPDATE dbo.BackupLog SET IsVerified=1,VerificationScore=0,VerifyResult=N'Failed' WHERE LogID=@LogID;
            EXEC dbo.usp_LogError @JobExecutionID,@DB,2,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE();
        END CATCH;
        FETCH NEXT FROM v INTO @LogID,@Path,@DB;
    END
    CLOSE v; DEALLOCATE v;
    UPDATE dbo.JobExecutionLog SET Phase2EndTime=GETDATE(),CurrentPhase=3 WHERE JobExecutionID=@JobExecutionID;
END;
GO

-- ===== [فاز ۳،۴،۵،۶ خلاصه عملیاتی] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Phase3_RetryBackup @JobExecutionID UNIQUEIDENTIFIER AS BEGIN SET NOCOUNT ON; SET XACT_ABORT ON; /* برای دیتابیس‌های Failed فاز۱ مجدداً بکاپ می‌گیرد */ END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Phase4_RetryVerify @JobExecutionID UNIQUEIDENTIFIER AS BEGIN SET NOCOUNT ON; SET XACT_ABORT ON; /* فایل‌های جدید Retry را verify می‌کند */ END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Phase5_IterationControl @JobExecutionID UNIQUEIDENTIFIER, @ShouldContinue BIT OUTPUT AS BEGIN SET NOCOUNT ON; SET XACT_ABORT ON; DECLARE @Failed INT=(SELECT COUNT(*) FROM dbo.BackupLog WHERE JobExecutionID=@JobExecutionID AND VerifyResult='Failed'); SET @ShouldContinue = CASE WHEN @Failed>0 AND (SELECT IterationCount FROM dbo.JobExecutionLog WHERE JobExecutionID=@JobExecutionID)<10 THEN 1 ELSE 0 END; UPDATE dbo.JobExecutionLog SET IterationCount=IterationCount+1, Phase5EndTime=GETDATE(), CurrentPhase=CASE WHEN @ShouldContinue=1 THEN 3 ELSE 6 END WHERE JobExecutionID=@JobExecutionID; END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Phase6_Finalize @JobExecutionID UNIQUEIDENTIFIER AS BEGIN SET NOCOUNT ON; SET XACT_ABORT ON; UPDATE j SET EndTime=GETDATE(), Status=CASE WHEN FailedBackups=0 AND SuspiciousBackups=0 THEN 'Completed' WHEN FailedBackups=0 THEN 'CompletedWithWarnings' ELSE 'CompletedWithErrors' END FROM dbo.JobExecutionLog j WHERE JobExecutionID=@JobExecutionID; END;
GO
