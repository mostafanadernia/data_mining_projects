USE [msdb];
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Hyperion_Nightly_Full_Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Hyperion_Nightly_Full_Backup';
GO

USE [BackupLogDB];
GO

DROP PROCEDURE IF EXISTS dbo.usp_BackupController_Main;
DROP PROCEDURE IF EXISTS dbo.usp_Phase1_InitialBackup;
DROP PROCEDURE IF EXISTS dbo.usp_Phase2_VerifyAll;
DROP PROCEDURE IF EXISTS dbo.usp_Phase3_RetryBackup;
DROP PROCEDURE IF EXISTS dbo.usp_Phase4_RetryVerify;
DROP PROCEDURE IF EXISTS dbo.usp_Phase5_IterationControl;
DROP PROCEDURE IF EXISTS dbo.usp_Phase6_Finalize;
DROP PROCEDURE IF EXISTS dbo.usp_Backup_UNC;
DROP PROCEDURE IF EXISTS dbo.usp_Backup_NetUse;
DROP PROCEDURE IF EXISTS dbo.usp_Backup_xpCmdshell;
DROP PROCEDURE IF EXISTS dbo.usp_LogError;
DROP PROCEDURE IF EXISTS dbo.usp_ValidatePath;
DROP PROCEDURE IF EXISTS dbo.usp_GenerateFileName;
DROP PROCEDURE IF EXISTS dbo.usp_CalculateRequiredSpace;
DROP PROCEDURE IF EXISTS dbo.usp_UpdateJobProgress;
DROP PROCEDURE IF EXISTS dbo.usp_CleanupOldFiles;
DROP PROCEDURE IF EXISTS dbo.usp_SendNotification;
DROP PROCEDURE IF EXISTS dbo.usp_Enable_xpCmdshell;
DROP PROCEDURE IF EXISTS dbo.usp_Disable_xpCmdshell;
DROP PROCEDURE IF EXISTS dbo.usp_ExecuteWhitelistedCmd;
DROP PROCEDURE IF EXISTS dbo.usp_AuditXpCmdshell;
DROP PROCEDURE IF EXISTS dbo.usp_CheckDiskSpace;
DROP PROCEDURE IF EXISTS dbo.usp_GetThrottleDelay;
DROP PROCEDURE IF EXISTS dbo.usp_DecryptPassword;
DROP FUNCTION IF EXISTS dbo.ufn_IsValidBackupPath;
DROP FUNCTION IF EXISTS dbo.ufn_CalcRequiredSpaceMB;
DROP FUNCTION IF EXISTS dbo.ufn_GetGrowthFactor30Days;
DROP FUNCTION IF EXISTS dbo.ufn_GetVerifyResultByScore;

DROP TABLE IF EXISTS dbo.xpCmdshellAudit, dbo.DiskSpaceHistory, dbo.RetryQueue, dbo.ErrorLog, dbo.DeleteBadLog, dbo.DeleteOldLog, dbo.VerifyLog, dbo.BackupLog, dbo.JobExecutionLog, dbo.BackupSettings, dbo.BackupDatabases;
GO

USE [master];
GO
DROP DATABASE IF EXISTS [BackupLogDB];
GO
