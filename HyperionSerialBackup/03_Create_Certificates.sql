USE [master]; -- استفاده از master برای ایجاد کلید اصلی و گواهی سطح سرور
GO -- پایان batch

-- ===== [ایجاد کلید اصلی در master] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##') -- بررسی وجود Master Key
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ChangeThis_Strong_MasterKey_Password_Immediately!'; -- ایجاد Master Key
END;
GO -- پایان batch

-- ===== [ایجاد گواهی در master برای مدیریت کلیدها] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'BackupSystemCertificate') -- بررسی وجود گواهی
BEGIN
    CREATE CERTIFICATE BackupSystemCertificate WITH SUBJECT = 'Certificate for Hyperion backup credentials in master', EXPIRY_DATE = '2099-12-31'; -- ایجاد گواهی master
END;
GO -- پایان batch

USE [BackupLogDB]; -- رفتن به دیتابیس عملیاتی
GO -- پایان batch

-- ===== [ایجاد Master Key در BackupLogDB] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##') -- بررسی وجود Master Key دیتابیس
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ChangeThis_Strong_BackupLogDB_MasterKey_Password_Immediately!'; -- ایجاد Master Key دیتابیس
END;
GO -- پایان batch

-- ===== [ایجاد گواهی محلی دیتابیس عملیاتی] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'BackupSystemCertificate') -- بررسی وجود گواهی محلی
BEGIN
    CREATE CERTIFICATE BackupSystemCertificate WITH SUBJECT = 'Certificate for Hyperion backup credentials in BackupLogDB', EXPIRY_DATE = '2099-12-31'; -- ایجاد گواهی محلی
END;
GO -- پایان batch

-- ===== [ایجاد کلید متقارن AES_256] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'BackupSymmetricKey') -- بررسی وجود symmetric key
BEGIN
    CREATE SYMMETRIC KEY BackupSymmetricKey WITH ALGORITHM = AES_256 ENCRYPTION BY CERTIFICATE BackupSystemCertificate; -- ایجاد کلید متقارن
END;
GO -- پایان batch
