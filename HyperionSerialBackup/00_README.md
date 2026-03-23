# Hyperion Serial Backup System / سامانه پشتیبان‌گیری سریال هایپریون

## English Overview
This package implements a **strictly serial, 6-phase SQL Server backup system** for mission-critical environments.

### Included deliverables
- 01_Create_Database.sql
- 02_Create_Tables.sql
- 03_Create_Certificates.sql
- 04_Create_Functions.sql
- 05_Create_Utility_Procedures.sql
- 06_Create_Phase_Procedures.sql
- 07_Create_Main_Controller.sql
- 08_Create_Network_Procedures.sql
- 09_Insert_Sample_Data.sql
- 10_Create_SQLAgent_Job.sql
- 11_Test_Scripts.sql
- 12_Monitoring_Queries.sql
- 13_Maintenance_Scripts.sql
- 14_Rollback_Script.sql

### Deployment order
Run files in numeric order.

### Safety notes
- Keep `xp_cmdshell` disabled by default.
- Enable only through controlled procedures and log all commands.
- Validate every path and credential before use.

---

## راهنمای فارسی
این بسته یک سامانه **پشتیبان‌گیری کاملاً سریالی و فازبندی‌شده (۶ فاز)** برای SQL Server ارائه می‌دهد.

### ویژگی‌های کلیدی
- اجرای کاملاً ترتیبی فازها (بدون همپوشانی)
- لاگ‌گیری کامل برای بازسازی رویدادها در ماه‌های بعد
- مکانیزم Retry فقط برای دیتابیس‌های خراب
- راستی‌آزمایی سه‌مرحله‌ای (VERIFYONLY + HEADERONLY + امتیازدهی)
- سیاست نگهداری (Retention) پس از تایید سلامت فایل

### روش نصب
اسکریپت‌ها را دقیقاً به ترتیب شماره اجرا کنید.

### نکات امنیتی
- `xp_cmdshell` به صورت پیش‌فرض غیرفعال باشد.
- تمام دستورات سیستمی در جدول `xpCmdshellAudit` ثبت شوند.
- رمزهای عبور شبکه فقط به‌صورت رمزگذاری‌شده نگهداری شوند.


### Project metadata
- q.json (prompt metadata and repository hint)

### یادداشت پروژه
- فایل `q.json` به عنوان متادیتای پروژه اضافه شده است.
