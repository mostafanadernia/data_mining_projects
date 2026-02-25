USE [BackupLogDB];
GO

-- ===== [کنترلر اصلی اجرای سریالی فازها] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_BackupController_Main
    @DatabaseName NVARCHAR(128) = NULL,
    @ForceRestart BIT = 0,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @JobExecutionID UNIQUEIDENTIFIER;
    SELECT TOP(1) @JobExecutionID = JobExecutionID FROM dbo.JobExecutionLog WHERE Status='Running' ORDER BY StartTime DESC; -- پیدا کردن job ناتمام

    IF @JobExecutionID IS NULL OR @ForceRestart = 1
    BEGIN
        SET @JobExecutionID = NEWID();
        INSERT INTO dbo.JobExecutionLog(JobExecutionID, JobName, StartTime, Status, CurrentPhase)
        VALUES(@JobExecutionID, N'Nightly_Full_Backup', GETDATE(), N'Running', 1);
    END

    BEGIN TRY
        EXEC dbo.usp_Phase1_InitialBackup @JobExecutionID, @DatabaseName, @DebugMode;
    END TRY BEGIN CATCH EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,1,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;

    BEGIN TRY
        EXEC dbo.usp_Phase2_VerifyAll @JobExecutionID;
    END TRY BEGIN CATCH EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,2,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;

    DECLARE @LoopActive BIT = 1;
    WHILE @LoopActive = 1
    BEGIN
        BEGIN TRY EXEC dbo.usp_Phase3_RetryBackup @JobExecutionID; END TRY BEGIN CATCH EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,3,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;
        BEGIN TRY EXEC dbo.usp_Phase4_RetryVerify @JobExecutionID; END TRY BEGIN CATCH EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,4,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;
        BEGIN TRY EXEC dbo.usp_Phase5_IterationControl @JobExecutionID, @LoopActive OUTPUT; END TRY BEGIN CATCH SET @LoopActive = 0; EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,5,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;
    END

    BEGIN TRY
        EXEC dbo.usp_Phase6_Finalize @JobExecutionID;
    END TRY BEGIN CATCH EXEC dbo.usp_LogError @JobExecutionID,@DatabaseName,6,ERROR_MESSAGE(),ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(); END CATCH;

    SELECT @JobExecutionID AS JobExecutionID;
END;
GO
