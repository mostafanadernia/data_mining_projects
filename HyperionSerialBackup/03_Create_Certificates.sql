USE [master]; -- استفاده از master برای اشیای امنیتی
GO -- پایان batch

-- ===== [ایجاد Master Key] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##') -- بررسی وجود کلید اصلی
BEGIN -- شروع ایجاد کلید اصلی
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ChangeThis_Strong_MasterKey_Password_Immediately!'; -- ایجاد کلید اصلی با رمز قوی
END; -- پایان ایجاد کلید اصلی
GO -- پایان batch

-- ===== [ایجاد گواهی و کلید متقارن] ===== --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'BackupSystemCertificate') -- بررسی وجود certificate
BEGIN -- شروع ساخت certificate
    CREATE CERTIFICATE BackupSystemCertificate -- ایجاد certificate برای رمزنگاری
    WITH SUBJECT = 'Certificate for Hyperion backup credentials', EXPIRY_DATE = '2099-12-31'; -- مشخصات certificate
END; -- پایان ساخت certificate
GO -- پایان batch

USE [BackupLogDB]; -- رفتن به دیتابیس عملیاتی
GO -- پایان batch

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'BackupSymmetricKey') -- بررسی وجود symmetric key
BEGIN -- شروع ساخت symmetric key
    CREATE SYMMETRIC KEY BackupSymmetricKey -- ایجاد کلید متقارن
    WITH ALGORITHM = AES_256 -- الگوریتم رمزنگاری
    ENCRYPTION BY CERTIFICATE BackupSystemCertificate; -- اتصال کلید به certificate
END; -- پایان ساخت symmetric key
GO -- پایان batch
