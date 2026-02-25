USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [تابع اعتبارسنجی مسیر] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_IsValidBackupPath (@Path NVARCHAR(500)) -- تعریف تابع اعتبارسنجی مسیر
RETURNS BIT -- خروجی باینری معتبر/نامعتبر
AS -- شروع بدنه تابع
BEGIN -- شروع بدنه منطقی
    DECLARE @IsValid BIT = 0; -- مقدار پیش‌فرض نامعتبر
    IF @Path IS NOT NULL AND LEN(@Path) BETWEEN 3 AND 260 -- بررسی طول مسیر
       AND (@Path LIKE '[A-Z]:\%' OR @Path LIKE '\\%\%') -- بررسی الگوی local یا UNC
       AND @Path NOT LIKE '%..%' -- جلوگیری از traversal
       AND @Path NOT LIKE '%;%' -- جلوگیری از تزریق cmd/sql
    BEGIN -- مسیر معتبر
        SET @IsValid = 1; -- تنظیم مسیر معتبر
    END; -- پایان شرط
    RETURN @IsValid; -- بازگشت نتیجه
END; -- پایان تابع
GO -- پایان batch

-- ===== [تابع محاسبه فضای موردنیاز] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_CalcRequiredSpaceMB (@DatabaseSizeMB DECIMAL(18,2), @GrowthFactor DECIMAL(5,2)) -- تابع فرمول ظرفیت
RETURNS BIGINT -- خروجی فضای موردنیاز MB
AS -- شروع تابع
BEGIN -- شروع منطق
    DECLARE @CompressionFactor DECIMAL(5,2) = 0.35; -- ضریب فشرده‌سازی
    DECLARE @SafetyMargin DECIMAL(5,2) = 0.25; -- حاشیه اطمینان
    DECLARE @EmergencyBufferMB BIGINT = 51200; -- بافر اضطراری 50GB
    DECLARE @Result BIGINT; -- متغیر خروجی
    SET @Result = CEILING((@DatabaseSizeMB * @CompressionFactor * (1 + @SafetyMargin) * ISNULL(@GrowthFactor,1.0)) + @EmergencyBufferMB); -- پیاده‌سازی فرمول
    RETURN @Result; -- بازگشت خروجی
END; -- پایان تابع
GO -- پایان batch
