-- ===== [ایجاد پایگاه داده اصلی لاگ پشتیبان] ===== --
USE [master]; -- رفتن به دیتابیس master برای ایجاد دیتابیس جدید
GO -- پایان batch

IF DB_ID(N'BackupLogDB') IS NULL -- بررسی اینکه دیتابیس قبلاً ایجاد نشده باشد
BEGIN -- شروع بلوک ایجاد دیتابیس
    CREATE DATABASE [BackupLogDB] -- ایجاد دیتابیس اصلی
    CONTAINMENT = NONE -- تنظیم حالت containment استاندارد
    ON PRIMARY -- تعریف فایل گروه اصلی
    (
        NAME = N'BackupLogDB_Primary', -- نام منطقی فایل داده
        FILENAME = N'D:\SQLData\BackupLogDB_Primary.mdf', -- مسیر فایل داده
        SIZE = 1024MB, -- اندازه اولیه فایل داده
        FILEGROWTH = 256MB -- رشد مرحله‌ای فایل داده
    ) -- پایان فایل داده اصلی
    LOG ON -- تعریف فایل لاگ
    (
        NAME = N'BackupLogDB_Log', -- نام منطقی فایل لاگ
        FILENAME = N'E:\SQLLog\BackupLogDB_Log.ldf', -- مسیر فایل لاگ
        SIZE = 1024MB, -- اندازه اولیه فایل لاگ
        FILEGROWTH = 256MB -- رشد مرحله‌ای فایل لاگ
    ); -- پایان دستور ایجاد دیتابیس
END; -- پایان بلوک ایجاد دیتابیس
GO -- پایان batch

ALTER DATABASE [BackupLogDB] SET RECOVERY FULL; -- تنظیم مدل بازیابی کامل برای سناریوهای حساس
ALTER DATABASE [BackupLogDB] SET PAGE_VERIFY CHECKSUM; -- فعال‌سازی checksum برای تشخیص خرابی صفحات
GO -- پایان batch
