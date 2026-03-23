USE [BackupLogDB];
GO

SELECT * FROM dbo.JobExecutionLog WHERE Status='Running' ORDER BY StartTime DESC; -- وضعیت جاری Job
SELECT b.DatabaseName,b.BackupFileName,b.VerifyResult,b.RetryCount,e.ErrorMessage,e.ErrorSeverity FROM dbo.BackupLog b LEFT JOIN dbo.ErrorLog e ON b.JobExecutionID=e.JobExecutionID AND b.DatabaseName=e.DatabaseName AND e.Phase=2 WHERE b.VerifyResult IN ('Failed','Suspicious'); -- فایل‌های خراب/مشکوک
SELECT d.DatabaseName,h.FreeSpaceGB,h.RequiredSpaceGB,(h.FreeSpaceGB-h.RequiredSpaceGB) AS SurplusGB,h.FreePercentage FROM dbo.DiskSpaceHistory h JOIN dbo.BackupDatabases d ON h.DatabaseID=d.DatabaseID WHERE h.CheckTime > DATEADD(HOUR,-24,GETDATE()) ORDER BY SurplusGB ASC; -- وضعیت فضای دیسک
SELECT DatabaseName,DATEDIFF(MINUTE,StartTime,GETDATE()) AS RunningMinutes FROM dbo.BackupLog WHERE EndTime IS NULL AND StartTime < DATEADD(HOUR,-2,GETDATE()); -- عملیات طولانی
SELECT d.DatabaseName,r.RetryCount,r.NextRetryTime,r.LastError FROM dbo.RetryQueue r JOIN dbo.BackupDatabases d ON r.DatabaseID=d.DatabaseID WHERE r.ProcessedDate IS NULL ORDER BY r.NextRetryTime; -- صف retry
GO
