USE [BackupLogDB];
GO

INSERT INTO dbo.BackupSettings(DefaultBackupPath,DefaultMinFilesToKeep,DefaultMaxRetry,GlobalThrottleDelay,EnableEmailNotification,EmailRecipients,EnableSMSAlert,SMSRecipients,EnableTeamsNotification,TeamsWebhookURL,RetentionCleanupEnabled)
VALUES(N'D:\Backups',7,5,30,1,N'dba@company.com;backup-team@company.com;storage-admin@company.com',1,N'+1234567890',1,N'https://company.webhook.office.com/webhookb2/...',1);

INSERT INTO dbo.BackupDatabases(DatabaseName,BackupPath,BackupType,NetworkUsername,NetworkPassword,DriveLetter,MinFilesToKeep,MaxRetryAttempts,Priority)
VALUES
(N'FinanceDB',N'D:\Backups',N'Local',NULL,NULL,NULL,7,5,1),
(N'CustomerDB_Prod',N'\\192.168.1.100\backups',N'UNC',N'localuser',0x00,NULL,10,3,2),
(N'OrderDB_Europe',N'\\192.168.2.50\share',N'NetUse',N'backupuser',0x00,'Z',5,7,3),
(N'HR_System',N'E:\SQLBackups',N'Local',NULL,NULL,NULL,14,5,4),
(N'InventoryDB',N'\\10.0.0.150\backups',N'UNC',N'svc_backup',0x00,NULL,7,5,5),
(N'AnalyticsDB',N'\\192.168.5.75\archive',N'NetUse',N'archive_user',0x00,'Y',3,10,6);
GO
