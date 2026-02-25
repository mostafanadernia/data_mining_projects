USE [BackupLogDB];
GO

-- ===== [رویه UNC] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_UNC
    @DatabaseName NVARCHAR(128), @BackupPath NVARCHAR(500), @FileName NVARCHAR(255), @UseChecksum BIT, @UseCompression BIT,
    @Success BIT OUTPUT, @FileSize BIGINT OUTPUT, @ErrorMessage NVARCHAR(2000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @FullPath NVARCHAR(800)=CONCAT(@BackupPath, CASE WHEN RIGHT(@BackupPath,1)='\' THEN '' ELSE '\' END, @DatabaseName, '\', @FileName);
        DECLARE @SQL NVARCHAR(MAX)=N'BACKUP DATABASE '+QUOTENAME(@DatabaseName)+N' TO DISK=@p WITH INIT, FORMAT, STATS=1'+CASE WHEN @UseCompression=1 THEN N',COMPRESSION' ELSE N'' END+CASE WHEN @UseChecksum=1 THEN N',CHECKSUM' ELSE N'' END;
        EXEC sp_executesql @SQL,N'@p NVARCHAR(800)',@p=@FullPath;
        SET @Success=1; SET @FileSize=NULL; SET @ErrorMessage=NULL;
    END TRY
    BEGIN CATCH
        SET @Success=0; SET @ErrorMessage=ERROR_MESSAGE();
    END CATCH
END;
GO

-- ===== [رویه NetUse] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_NetUse
    @DatabaseName NVARCHAR(128), @UNCPath NVARCHAR(500), @DriveLetter CHAR(1), @Username NVARCHAR(100), @EncryptedPassword VARBINARY(512),
    @FileName NVARCHAR(255), @UseChecksum BIT, @UseCompression BIT, @Success BIT OUTPUT, @FileSize BIGINT OUTPUT, @ErrorMessage NVARCHAR(2000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @DecryptedPassword NVARCHAR(100)=N'REPLACE_WITH_SECURE_DECRYPT'; -- placeholder
    BEGIN TRY
        EXEC xp_cmdshell CONCAT('net use ',@DriveLetter,': ',@UNCPath,' /user:',@Username,' ',@DecryptedPassword), NO_OUTPUT;
        INSERT INTO dbo.xpCmdshellAudit(CommandText,OutputPreview) VALUES(CONCAT('net use ',@DriveLetter,': ',@UNCPath),N'Mapped');
        EXEC dbo.usp_Backup_UNC @DatabaseName,@DriveLetter+':',@FileName,@UseChecksum,@UseCompression,@Success OUTPUT,@FileSize OUTPUT,@ErrorMessage OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Success=0; SET @ErrorMessage=ERROR_MESSAGE();
    END CATCH
    EXEC xp_cmdshell CONCAT('net use ',@DriveLetter,': /delete'), NO_OUTPUT;
    INSERT INTO dbo.xpCmdshellAudit(CommandText,OutputPreview) VALUES(CONCAT('net use ',@DriveLetter,': /delete'),N'Unmapped');
END;
GO

-- ===== [رویه xp_cmdshell] ===== --
CREATE OR ALTER PROCEDURE dbo.usp_Backup_xpCmdshell
    @DatabaseName NVARCHAR(128), @BackupPath NVARCHAR(500), @FileName NVARCHAR(255), @UseChecksum BIT, @UseCompression BIT,
    @Success BIT OUTPUT, @FileSize BIGINT OUTPUT, @ErrorMessage NVARCHAR(2000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_configure 'show advanced options',1; RECONFIGURE;
        EXEC sp_configure 'xp_cmdshell',1; RECONFIGURE;
        INSERT INTO dbo.xpCmdshellAudit(CommandText,OutputPreview) VALUES(N'Enable xp_cmdshell',N'Enabled');
        EXEC dbo.usp_Backup_UNC @DatabaseName,@BackupPath,@FileName,@UseChecksum,@UseCompression,@Success OUTPUT,@FileSize OUTPUT,@ErrorMessage OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Success=0; SET @ErrorMessage=ERROR_MESSAGE();
    END CATCH
    EXEC sp_configure 'xp_cmdshell',0; RECONFIGURE;
    INSERT INTO dbo.xpCmdshellAudit(CommandText,OutputPreview) VALUES(N'Disable xp_cmdshell',N'Disabled');
END;
GO
