USE [msdb]; -- انتخاب دیتابیس msdb برای مدیریت SQL Agent
GO -- پایان batch

-- ===== [حذف Job قبلی در صورت وجود] ===== --
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Hyperion_Nightly_Full_Backup') -- بررسی وجود job قبلی
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'Hyperion_Nightly_Full_Backup'; -- حذف job قبلی برای جلوگیری از تداخل
END;
GO -- پایان batch

-- ===== [ایجاد Job زمان‌بندی‌شده پشتیبان‌گیری شبانه] ===== --
EXEC msdb.dbo.sp_add_job @job_name = N'Hyperion_Nightly_Full_Backup', @enabled = 1, @description = N'Serial multi-phase backup job'; -- ایجاد job جدید
EXEC msdb.dbo.sp_add_jobstep @job_name = N'Hyperion_Nightly_Full_Backup', @step_name = N'Run Controller', @subsystem = N'TSQL', @database_name = N'BackupLogDB', @command = N'EXEC dbo.usp_BackupController_Main @DatabaseName = NULL, @ForceRestart = 0, @DebugMode = 0;'; -- افزودن step اجرای کنترلر
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'Nightly_2200_Hyperion', @enabled = 1, @freq_type = 4, @freq_interval = 1, @active_start_time = 220000; -- ایجاد schedule روزانه ساعت 22:00
EXEC msdb.dbo.sp_attach_schedule @job_name = N'Hyperion_Nightly_Full_Backup', @schedule_name = N'Nightly_2200_Hyperion'; -- اتصال schedule به job
EXEC msdb.dbo.sp_add_jobserver @job_name = N'Hyperion_Nightly_Full_Backup'; -- اتصال job به سرور جاری
GO -- پایان batch
