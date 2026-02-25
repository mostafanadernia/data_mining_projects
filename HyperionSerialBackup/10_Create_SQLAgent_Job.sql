USE [msdb];
GO

-- ایجاد Job زمان‌بندی‌شده برای اجرای شبانه
EXEC msdb.dbo.sp_add_job @job_name = N'Hyperion_Nightly_Full_Backup', @enabled = 1, @description = N'Serial multi-phase backup job';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'Hyperion_Nightly_Full_Backup', @step_name = N'Run Controller', @subsystem = N'TSQL', @database_name = N'BackupLogDB', @command = N'EXEC dbo.usp_BackupController_Main @DatabaseName = NULL, @ForceRestart = 0, @DebugMode = 0;';
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'Nightly_2200', @enabled = 1, @freq_type = 4, @freq_interval = 1, @active_start_time = 220000;
EXEC msdb.dbo.sp_attach_schedule @job_name = N'Hyperion_Nightly_Full_Backup', @schedule_name = N'Nightly_2200';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'Hyperion_Nightly_Full_Backup';
GO
