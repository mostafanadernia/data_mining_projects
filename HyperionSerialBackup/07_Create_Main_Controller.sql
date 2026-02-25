USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [کنترلر اصلی فازهای سریالی] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_BackupController_Main -- تعریف کنترلر اصلی
    @DatabaseName NVARCHAR(128) = NULL, -- دیتابیس اختیاری
    @ForceRestart BIT = 0, -- اجبار شروع مجدد
    @DebugMode BIT = 0 -- حالت دیباگ
AS
BEGIN
    SET NOCOUNT ON; -- کاهش نویز
    SET XACT_ABORT ON; -- مدیریت خطا

    DECLARE @JobExecutionID UNIQUEIDENTIFIER; -- شناسه job
    DECLARE @CurrentPhase INT = 1; -- فاز جاری
    DECLARE @LoopActive BIT = 1; -- وضعیت حلقه

    IF @ForceRestart = 0 -- اگر اجبار restart نبود
    BEGIN
        SELECT TOP(1) @JobExecutionID = JobExecutionID, @CurrentPhase = CurrentPhase -- بازیابی آخرین job در حال اجرا
        FROM dbo.JobExecutionLog -- جدول job
        WHERE Status = N'Running' -- فقط jobهای running
        ORDER BY StartTime DESC; -- آخرین job
    END;

    IF @JobExecutionID IS NULL -- اگر job قابل resume پیدا نشد
    BEGIN
        SET @JobExecutionID = NEWID(); -- تولید شناسه job جدید
        INSERT INTO dbo.JobExecutionLog (JobExecutionID, JobName, StartTime, Status, CurrentPhase, IterationCount) -- درج رکورد شروع job
        VALUES (@JobExecutionID, N'Nightly_Full_Backup', GETDATE(), N'Running', 1, 0); -- مقادیر اولیه
        SET @CurrentPhase = 1; -- شروع از فاز 1
    END;

    BEGIN TRY
        IF @CurrentPhase <= 1 EXEC dbo.usp_Phase1_InitialBackup @JobExecutionID, @DatabaseName, @DebugMode, 0; -- اجرای فاز 1
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 1, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase1'; -- ثبت خطای فاز1
    END CATCH;

    BEGIN TRY
        IF @CurrentPhase <= 2 EXEC dbo.usp_Phase2_VerifyAll @JobExecutionID; -- اجرای فاز 2
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 2, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase2'; -- ثبت خطای فاز2
    END CATCH;

    WHILE @LoopActive = 1 -- حلقه فازهای 3 تا 5
    BEGIN
        BEGIN TRY
            EXEC dbo.usp_Phase3_RetryBackup @JobExecutionID; -- اجرای فاز 3
        END TRY
        BEGIN CATCH
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 3, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase3'; -- ثبت خطای فاز3
        END CATCH;

        BEGIN TRY
            EXEC dbo.usp_Phase4_RetryVerify @JobExecutionID; -- اجرای فاز 4
        END TRY
        BEGIN CATCH
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 4, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase4'; -- ثبت خطای فاز4
        END CATCH;

        BEGIN TRY
            EXEC dbo.usp_Phase5_IterationControl @JobExecutionID, @LoopActive OUTPUT; -- اجرای فاز 5
        END TRY
        BEGIN CATCH
            SET @LoopActive = 0; -- توقف حلقه در خطای کنترل
            EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 5, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase5'; -- ثبت خطای فاز5
        END CATCH;
    END;

    BEGIN TRY
        EXEC dbo.usp_Phase6_Finalize @JobExecutionID; -- اجرای فاز 6
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_LogError @JobExecutionID, @DatabaseName, 6, ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), N'Controller catch phase6'; -- ثبت خطای فاز6
        UPDATE dbo.JobExecutionLog SET EndTime = GETDATE(), Status = N'CompletedWithErrors' WHERE JobExecutionID = @JobExecutionID; -- ثبت پایان با خطا
    END CATCH;

    SELECT @JobExecutionID AS JobExecutionID; -- خروجی شناسه job
END;
GO -- پایان batch
