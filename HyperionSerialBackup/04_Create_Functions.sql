USE [BackupLogDB]; -- انتخاب دیتابیس عملیاتی
GO -- پایان batch

-- ===== [تابع اعتبارسنجی مسیر بکاپ] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_IsValidBackupPath ( -- تعریف تابع بررسی معتبر بودن مسیر
    @Path NVARCHAR(500) -- مسیر ورودی
)
RETURNS BIT -- خروجی معتبر/نامعتبر
AS
BEGIN
    DECLARE @IsValid BIT = 0; -- مقدار پیش‌فرض نامعتبر
    IF @Path IS NOT NULL -- بررسی null نبودن مسیر
       AND LEN(@Path) BETWEEN 3 AND 260 -- کنترل طول استاندارد مسیر
       AND @Path NOT LIKE N'%..%' -- جلوگیری از traversal
       AND @Path NOT LIKE N'%;%' -- جلوگیری از تزریق دستور
       AND @Path NOT LIKE N'%|%' -- جلوگیری از pipe command
       AND @Path NOT LIKE N'%"%' -- جلوگیری از quote injection
       AND @Path NOT LIKE N'%<%' -- جلوگیری از redirect injection
       AND @Path NOT LIKE N'%>%' -- جلوگیری از redirect injection
       AND ( -- بررسی یکی از الگوهای معتبر مسیر
            @Path LIKE N'[A-Z]:\%' -- الگوی local
            OR @Path LIKE N'\\%\%' -- الگوی UNC
       )
    BEGIN
        SET @IsValid = 1; -- مسیر معتبر اعلام می‌شود
    END;
    RETURN @IsValid; -- بازگشت نتیجه
END;
GO -- پایان batch

-- ===== [تابع محاسبه رشد 30 روزه دیتابیس] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_GetGrowthFactor30Days ( -- تعریف تابع ضریب رشد
    @DatabaseName NVARCHAR(128) -- نام دیتابیس
)
RETURNS DECIMAL(5,2) -- خروجی ضریب رشد
AS
BEGIN
    DECLARE @GrowthFactor DECIMAL(5,2) = 1.00; -- مقدار پیش‌فرض ضریب رشد
    DECLARE @CurrentMB DECIMAL(18,2); -- اندازه فعلی دیتابیس
    DECLARE @PastMB DECIMAL(18,2); -- اندازه گذشته دیتابیس

    SELECT @CurrentMB = SUM(size * 8.0 / 1024.0) -- محاسبه اندازه فعلی دیتابیس
    FROM sys.master_files -- منبع اندازه فایل‌ها
    WHERE database_id = DB_ID(@DatabaseName); -- فیلتر دیتابیس هدف

    SELECT TOP(1) @PastMB = DatabaseSizeGB * 1024.0 -- استفاده از آخرین تاریخچه ثبت‌شده
    FROM dbo.DiskSpaceHistory -- جدول تاریخچه فضای دیسک
    WHERE DatabaseID = (SELECT DatabaseID FROM dbo.BackupDatabases WHERE DatabaseName = @DatabaseName) -- یافتن رکورد دیتابیس
      AND CheckTime <= DATEADD(DAY, -30, GETDATE()) -- نمونه حداقل 30 روز قبل
    ORDER BY CheckTime DESC; -- نزدیک‌ترین نمونه 30 روز قبل

    IF ISNULL(@PastMB,0) > 0 -- بررسی موجود بودن نمونه معتبر
    BEGIN
        IF ((@CurrentMB - @PastMB) / NULLIF(@PastMB,0)) > 0.05 -- اگر رشد بیش از پنج درصد بود
        BEGIN
            SET @GrowthFactor = 1.10; -- افزایش 10 درصدی فضای موردنیاز
        END;
    END;

    RETURN @GrowthFactor; -- بازگشت ضریب نهایی
END;
GO -- پایان batch

-- ===== [تابع محاسبه دقیق فضای موردنیاز] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_CalcRequiredSpaceMB ( -- تعریف تابع محاسبه فضا
    @DatabaseSizeMB DECIMAL(18,2), -- اندازه دیتابیس بر حسب MB
    @GrowthFactor DECIMAL(5,2) -- ضریب رشد
)
RETURNS BIGINT -- خروجی فضای موردنیاز بر حسب MB
AS
BEGIN
    DECLARE @CompressionFactor DECIMAL(6,4) = 0.35; -- ضریب فشرده‌سازی
    DECLARE @SafetyMargin DECIMAL(6,4) = 0.25; -- حاشیه ایمنی
    DECLARE @EmergencyBufferMB BIGINT = 50 * 1024; -- بافر اضطراری 50 گیگ
    DECLARE @Required BIGINT; -- خروجی نهایی

    SET @Required = CEILING((ISNULL(@DatabaseSizeMB,0) * @CompressionFactor * (1 + @SafetyMargin) * ISNULL(@GrowthFactor,1.00)) + @EmergencyBufferMB); -- فرمول نهایی
    RETURN @Required; -- بازگشت خروجی
END;
GO -- پایان batch

-- ===== [تابع دسته‌بندی امتیاز سلامت] ===== --
CREATE OR ALTER FUNCTION dbo.ufn_GetVerifyResultByScore ( -- تعریف تابع نگاشت امتیاز
    @Score INT -- امتیاز محاسبه‌شده
)
RETURNS NVARCHAR(20) -- خروجی نتیجه راستی‌آزمایی
AS
BEGIN
    DECLARE @Result NVARCHAR(20) = N'Failed'; -- مقدار پیش‌فرض
    IF @Score >= 85 SET @Result = N'Success'; -- آستانه سالم
    ELSE IF @Score >= 70 SET @Result = N'Warning'; -- آستانه هشدار
    ELSE IF @Score >= 50 SET @Result = N'Suspicious'; -- آستانه مشکوک
    RETURN @Result; -- بازگشت نتیجه
END;
GO -- پایان batch
