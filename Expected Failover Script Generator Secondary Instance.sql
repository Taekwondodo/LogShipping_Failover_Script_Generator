/*
Run this script on the original secondary instance.
Use this script to produce a T-SQL script to run on the secondary instances of a logshipping configuration in order to failover to it.
*/

set nocount, arithabort, xact_abort on 

go

use master;
go

declare @backupFilePath nvarchar(260)
      , @databaseFilter nvarchar(128)
      , @debug          bit
      , @exclude_system bit;

set @debug = 1;
set @exclude_system = 1; --So system tables are excluded

--set @databaseFilter = N'Footprints';

--================================
--
--Instead of using the registry to find the backup we'll use msdb.dbo.log_shipping_secondary_databases
--

if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';


declare @databases table (
   secondary_id     uniqueidentifier not null primary key
  ,database_name    nvarchar(128) not null 
  ,copy_job_id      uniqueidentifier not null
  ,restore_job_id   uniqueidentifier not null
);
insert into @databases (
   database_name
  ,secondary_id
  ,copy_job_id
  ,restore_job_id
)
select
   lssd.secondary_database as database_name, lssd.secondary_id as secondary_id, lss.copy_job_id, lss.restore_job_id
from
   msdb.dbo.log_shipping_secondary_databases AS lssd 
   LEFT JOIN sys.databases AS d ON (lssd.secondary_database = d.name)
   LEFT JOIN msdb.dbo.log_shipping_secondary AS lss  ON (lssd.secondary_id = lss.secondary_id)
--
--We don't want a db if it is offline, already restored, or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   AND (d.is_read_only = 1)
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lssd.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   PRINT N'There are no selected databases configured for logshipping as a secondary database';

select
   @databaseFilter as DatabaseFilter
 , @backupFilePath as BackupFilePath
 , @exclude_system as ExcludeSystemDatabases;

if (@debug = 1) begin

   select
      *
   from
      @databases AS d
   order by
      d.database_name;

end;

--Table that contains job information

DECLARE @jobs TABLE (
   job_id            uniqueidentifier NOT NULL PRIMARY KEY
  ,job_name          nvarchar(128) NOT NULL
  ,avg_runtime       int NOT NULL --HHMMSS format
  ,target_database   nvarchar(128) NOT NULL
);

INSERT INTO @jobs (
  job_id
 ,job_name
 ,avg_runtime
 ,target_database
)
SELECT 
       sj.job_id AS job_id, MAX(sj.name), AVG(t2.Total_Seconds) AS avg_runtime, MAX(td.database_name) AS target_database
FROM
    @databases AS td 
    LEFT JOIN sys.databases AS d ON (td.database_name = d.name)
    RIGHT JOIN msdb.dbo.sysjobs AS sj ON (td.copy_job_id = sj.job_id OR td.restore_job_id = sj.job_id) 
    RIGHT JOIN msdb.dbo.sysjobhistory AS sjh ON (sjh.job_id = sj.job_id)
    OUTER APPLY (
         SELECT
            RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 2) AS Seconds
           ,SUBSTRING(RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 4), 1, 2) AS Minutes
           ,SUBSTRING(RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 6), 1, 2) AS Hours
    ) as t1
    OUTER APPLY (
          SELECT 
             CAST(t1.Hours AS INT) * 3600 + CAST(t1.Minutes AS INT) * 60 + CAST(t1.Seconds AS INT) AS Total_Seconds
    )as t2
              
--We don't want a job that isn't enabled

WHERE sjh.step_id = 0 
      AND sj.enabled = 1
      AND (d.state_desc = N'ONLINE')
      AND ((@databaseFilter is null) OR (d.name like N'%' + @databaseFilter + N'%'))
      AND td.database_name IS NOT NULL --this is here to filter out jobs within sysjobs that we don't want since all jobs are included with the right join to sysjobs

GROUP BY sj.job_id;


IF (@debug = 1) BEGIN

   SELECT * FROM @jobs AS ji ORDER BY job_name;

END;


--================================

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Use the following script to failover to the following databases, disabling their secondary instance jobs on ' + quotename(@@servername) + ':';
PRINT N'-- Run on the original secondary';
PRINT N'--';

DECLARE @databaseName     nvarchar(128)
       ,@secondaryID      nvarchar(60)
       ,@copyJobName      nvarchar(128)
       ,@restoreJobName   nvarchar(128)
       ,@copyID           uniqueidentifier
       ,@tailBackupName   nvarchar(128) --Used to ensure that the copy/restore jobs successfully apply the transaction log tail backup to their respective databases 
       ,@restoreID        uniqueidentifier    
       ,@maxlenDB         int
       ,@maxlenJob        int

SET @databaseName = N'';
SET @tailBackupName = N'%Transaction Log Tail Backup';
SET @maxlenDB = (select max(datalength(j.target_database)) from @jobs as j);
SET @maxlenJob = (select max(datalength(j.job_name)) from @jobs as j);

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@copyJobName = j.job_name 
     ,@restoreJobName = j2.job_name 
   FROM
      @databases AS d LEFT JOIN @jobs AS j ON (d.copy_job_id = j.job_id)
      LEFT JOIN @jobs as j2 ON(d.restore_job_id = j2.job_id)

   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT N'-- ' + LEFT(@databaseName + REPLICATE(N' ', @maxlenDB / 2), @maxlenDB / 2) + N'    ' + LEFT(@copyJobName + REPLICATE(N' ', @maxlenJob / 2), @maxlenJob / 2) + N'    ' + @restoreJobName ;

END;     

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
PRINT N'';

PRINT N'USE msdb';
PRINT N'';
PRINT N'GO';
PRINT N'';
PRINT N'--Table takes result of RESTORE HEADERONLY to ensure Transaction Log Tail Backup is copied over';
PRINT N'';
PRINT N'DECLARE #backupInfo TABLE';
PRINT N'(';
PRINT N' BackupName nvarchar(128),';
PRINT N' BackupDescription nvarchar(255),';
PRINT N' BackupType smallint,';
PRINT N' ExpirationDate datetime,';
PRINT N' Compressed tinyint,';
PRINT N' Position smallint,';
PRINT N' DeviceType tinyint,';
PRINT N' UserName nvarchar(128),';
PRINT N' ServerName nvarchar(128),';
PRINT N' DatabaseName nvarchar(128),';
PRINT N' DatabaseVersion int,';
PRINT N' DatabaseCreationDate datetime,';
PRINT N' BackupSize numeric(20, 0),';
PRINT N' FirstLSN numeric(25, 0),';
PRINT N' LastLSN numeric(25, 0),';
PRINT N' CheckpointLSN numeric(25, 0),';
PRINT N' DatabaseBackupLSN numeric(25, 0),';
PRINT N' BackupStartDate datetime,';
PRINT N' BackupFinishDate datetime,';
PRINT N' SortOrder smallint,';
PRINT N' [CodePage] smallint,';
PRINT N' UnicodeLocaleId int,';
PRINT N' UnicodeComparisonStyle int,';
PRINT N' CompatibilityLevel tinyint,';
PRINT N' SoftwareVendorId int,';
PRINT N' SoftwareVersionMajor int,';
PRINT N' SoftwareVersionMinor int,';
PRINT N' SoftwareVersionBuild int,';
PRINT N' MachineName nvarchar(128),';
PRINT N' Flags int,';
PRINT N' BindingId uniqueidentifier,';
PRINT N' RecoveryForkId uniqueidentifier,';
PRINT N' Collation nvarchar(128),';
PRINT N' FamilyGUID uniqueidentifier,';
PRINT N' HasBulkLoggedData bit,';
PRINT N' IsSnapshot bit,';
PRINT N' IsReadOnly bit,';
PRINT N' IsSingleUser bit,';
PRINT N' HasBackupChecksums bit,';
PRINT N' IsDamaged bit,';
PRINT N' BeginsLogChain bit,';
PRINT N' HasIncompleteMetaData bit,';
PRINT N' IsForceOffline bit,';
PRINT N' IsCopyOnly bit,';
PRINT N' FirstRecoveryForkID uniqueidentifier,';
PRINT N' ForkPointLSN numeric(25, 0),';
PRINT N' RecoveryModel nvarchar(60),';
PRINT N' DifferentialBaseLSN numeric(25, 0),';
PRINT N' DifferentialBaseGUID uniqueidentifier,';
PRINT N' BackupTypeDescription nvarchar(60),';
PRINT N' BackupSetGUID uniqueidentifier';
PRINT N')';
PRINT N'';
PRINT N'--#jobInfo takes the result of the sp xp_slqagent_enum_jobs';
PRINT N'-- xp_slqagent_enum_jobs is useful as it returns the ''running'' column which is how we''ll determine if a job is running';
PRINT N'';
PRINT N'DECLARE #job_info TABLE (job_id                UNIQUEIDENTIFIER NOT NULL,';
PRINT N'                         last_run_date         INT              NOT NULL,';
PRINT N'                         last_run_time         INT              NOT NULL,';
PRINT N'                         next_run_date         INT              NOT NULL,';
PRINT N'                         next_run_time         INT              NOT NULL,';
PRINT N'                         next_run_schedule_id  INT              NOT NULL,';
PRINT N'                         requested_to_run      INT              NOT NULL, -- BOOL';
PRINT N'                         request_source        INT              NOT NULL,';
PRINT N'                         request_source_id     sysname          COLLATE database_default NULL,';
PRINT N'                         running               INT              NOT NULL, -- BOOL';
PRINT N'                         current_step          INT              NOT NULL,';
PRINT N'                         current_retry_attempt INT              NOT NULL,';
PRINT N'                         job_state             INT              NOT NULL)';
PRINT N'';   
PRINT N'';
PRINT N'PRINT N''Starting failover to secondary databases. Disabling secondary jobs...'';';
PRINT N'PRINT N'''';';
PRINT N''; 

--Iterate through the job ids and generate scripts to disable them

DECLARE @jobName          nvarchar(128)
       ,@jobID            nvarchar(128)  
       ,@totalSeconds     int
       ,@avgRuntime       nvarchar(8);

set @jobName = N'';

WHILE EXISTS (SELECT * FROM @jobs AS j WHERE @jobName < j.job_name) BEGIN

   SELECT TOP 1
   @jobName = j.job_name
  ,@jobID = j.job_id
  ,@totalSeconds = j.avg_runtime
   FROM 
      @jobs AS j
   WHERE 
      (j.job_name > @jobName)
   ORDER BY
      j.job_name ASC;

   --Convert the int avg_runtime to a datetime format acceptable by WAITFOR DELAY

   SET @avgRuntime = CAST((@totalSeconds / 3600) AS nvarchar(2)) + ':' + CAST((@totalSeconds / 60 % 60) AS nvarchar(2)) + ':' + CAST((@totalSeconds % 60) AS nvarchar(2)) 

   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'BEGIN TRY';  
   PRINT N'';
   PRINT N'    DECLARE @retcode int';
   PRINT N'';
   PRINT N'    PRINT N''================================'';';
   PRINT N'    PRINT N''Disabling ' + quotename(@jobName) + N''';';
   PRINT N'';
   PRINT N'    --We Make sure the jobs aren''t running to avoid issuse with premature cancelation since they''re cmd commands';
   PRINT N'	';
   PRINT N'	INSERT INTO #jobInfo';
   PRINT N'	EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
   PRINT N'	';
   PRINT N'	WHILE EXISTS (SELECT * FROM #jobInfo as ji WHERE ji.job_id = ''' + @jobID + N''' AND ji.running <> 0)';
   PRINT N'	BEGIN';
   PRINT N'	    PRINT N''Waiting ' + @avgRuntime + N' for job to finish running' + N''';';
   PRINT N'	    WAITFOR DELAY ' + N'''' + @avgRuntime + N'''';
   PRINT N'	';
   PRINT N'	    DELETE FROM #jobInfo';
   PRINT N'	    INSERT INTO #jobInfo';
   PRINT N'	    EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
   PRINT N'	END;';
   PRINT N'	';

   --Attempting to disable a job that is already disabled is not an issue

   PRINT N'	    IF(@retCode = 1) ';
   PRINT N'	       BEGIN';
   PRINT N'	          --You''ll notice these empty print statements before error messages, they are a workaround for print messages not being outputted';
   PRINT N'	          --when a rollback is performed after them. Not sure why it happens, but others have experienced this as well';
   PRINT N'	          PRINT N'''';';
   PRINT N'	          PRINT N''Error disabling ' + quotename(@jobName) + N' Rolling back...'';';
   PRINT N'	          ROLLBACK TRANSACTION;';
   PRINT N'	          RETURN;';
   PRINT N'	       END';
   PRINT N'	    ELSE BEGIN';
   PRINT N'	       COMMIT TRANSACTION;'
   PRINT N'	       PRINT N''Job disabled successfully'';';
   PRINT N'	       PRINT N'''';';
   PRINT N'	    END;';
   PRINT N'';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''There was an error stopping/disabling ' + quotename(@jobName) + N'. Rolling back and quitting execution...'';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
END;


PRINT N'';
PRINT N'PRINT N''Running databases'''' secondary jobs to ensure their respective transaction log tail backups are applied...'';';
PRINT N'';

set @databaseName = N'';

--Iterate through the databases, running their jobs and then restoring them

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@secondaryID = d.secondary_id
     ,@copyJobName = j.job_name     
     ,@restoreJobName = j2.job_name 
     ,@copyID = d.copy_job_id --remove the ids if they aren't used
     ,@restoreID  = d.restore_job_id 
   FROM
      @databases AS d LEFT JOIN @jobs AS j ON (d.copy_job_id = j.job_id)
      LEFT JOIN @jobs AS j2 ON (d.restore_job_id = j2.job_id)
   WHERE 
      d.database_name > @databaseName
   ORDER BY 
      d.database_name ASC;

   PRINT N'GO';
   PRINT N'';
   PRINT N'--Run the copy job';
   PRINT N'';
   PRINT N'PRINT N''Running jobs for ' + quotename(@databaseName) + N'. Starting copy job...'';';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'DECLARE @retcode int';
   PRINT N'       ,@lastCopiedFile     nvarchar(500)';
   PRINT N'       ,@backupInfoCommand  nvarchar(1100)';
   PRINT N'';
   PRINT N'	EXEC @retcode = msdb.dbo.sp_start_job @job_name = ''' + @copyJobName + N'''';
   PRINT N'	    IF(@retcode <> 0) BEGIN';
   PRINT N'	       PRINT N'''';';
   PRINT N'	       PRINT N''Error running ' + quotename(@copyJobName) + N'. Rolling back...'';';
   PRINT N'	       ROLLBACK TRANSACTION;';
   PRINT N'	       RETURN;';
   PRINT N'	    END;';
   PRINT N'';
   PRINT N'	--Check to make sure the transaction log tail backup was copied';
   PRINT N'';
   PRINT N'	SELECT';
   PRINT N'	    @lastCopiedFile = lss.last_copied_file';
   PRINT N'	FROM';
   PRINT N'	    log_shipping_secondary AS lss';
   PRINT N'	WHERE';
   PRINT N'	    lss.secondary_id = ''' + @secondaryID + N''';';
   PRINT N'';
   PRINT N'	--Check to make sure @backupInfoCommand is correct';
   PRINT N'	SET @backupInfoCommand = N''RESTORE HEADERONLY FROM DISK = N'''''' + @lastCopiedFile + N'''''''''; 
   PRINT N'';
   PRINT N'	INSERT INTO #backupInfo('
   PRINT N'		 BackupName,';
   PRINT N'		 BackupDescription,';
   PRINT N'		 BackupType,';
   PRINT N'		 ExpirationDate,';
   PRINT N'		 Compressed,';
   PRINT N'		 Position,';
   PRINT N'		 DeviceType,';
   PRINT N'		 UserName,';
   PRINT N'		 ServerName,';
   PRINT N'		 DatabaseName,';
   PRINT N'		 DatabaseVersion,';
   PRINT N'		 DatabaseCreationDate,';
   PRINT N'		 BackupSize,';
   PRINT N'		 FirstLSN,';
   PRINT N'		 LastLSN,';
   PRINT N'		 CheckpointLSN,';
   PRINT N'		 DatabaseBackupLSN,';
   PRINT N'		 BackupStartDate,';
   PRINT N'		 BackupFinishDate,';
   PRINT N'		 SortOrder,';
   PRINT N'		 [CodePage],';
   PRINT N'		 UnicodeLocaleId,';
   PRINT N'		 UnicodeComparisonStyle,';
   PRINT N'		 CompatibilityLevel,';
   PRINT N'		 SoftwareVendorId,';
   PRINT N'		 SoftwareVersionMajor,';
   PRINT N'		 SoftwareVersionMinor,';
   PRINT N'		 SoftwareVersionBuild,';
   PRINT N'		 MachineName,';
   PRINT N'		 Flags,';
   PRINT N'		 BindingId,';
   PRINT N'		 RecoveryForkId,';
   PRINT N'		 Collation,';
   PRINT N'		 FamilyGUID,';
   PRINT N'		 HasBulkLoggedData,';
   PRINT N'		 IsSnapshot,';
   PRINT N'		 IsReadOnly,';
   PRINT N'		 IsSingleUser,';
   PRINT N'		 HasBackupChecksums,';
   PRINT N'		 IsDamaged,';
   PRINT N'		 BeginsLogChain,';
   PRINT N'		 HasIncompleteMetaData,';
   PRINT N'		 IsForceOffline,';
   PRINT N'		 IsCopyOnly,';
   PRINT N'		 FirstRecoveryForkID,';
   PRINT N'		 ForkPointLSN,';
   PRINT N'		 RecoveryModel,';
   PRINT N'		 DifferentialBaseLSN,';
   PRINT N'		 DifferentialBaseGUID,';
   PRINT N'		 BackupTypeDescription,';
   PRINT N'		 BackupSetGUID ';
   PRINT N'	)'
   PRINT N'	EXEC sp_executesql @backupInfoCommand';
   PRINT N'';
   PRINT N'	IF(EXISTS(SELECT * FROM #backupInfo AS bi WHERE bi.backupName LIKE ''' + @tailBackupName + N'''))BEGIN';
   PRINT N'	    COMMIT TRANSACTION;';
   PRINT N'	    PRINT N''Copy job successfully copied the Transaction Log Tail Backup. Starting restore job...'';';
   PRINT N'	    DELETE FROM #backupInfo;';
   PRINT N'	END';
   PRINT N'	ELSE BEGIN';
   PRINT N'	    PRINT N'''';';
   PRINT N'	    PRINT N''' + quotename(@copyJobName) + N' did not copy over the Transaction Log Tail Backup. Check to make sure the file name follows the same format'';';
   PRINT N'	    PRINT N''as the backups output by the jobs themselves. This includes being in UTC. Rolling Back and quitting execution...'';';
   PRINT N'	    ROLLBACK TRANSACTION;';
   PRINT N'	    RETURN;';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''And error was encountered while running/checking copy job ' + quotename(@copyJobName) + N'. Rolling Back and quitting execution...'';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';
   PRINT N'--Run restore job';
   PRINT N'';
   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'DECLARE @retcode int';
   PRINT N'';
   PRINT N'	EXEC @retcode = msdb.dbo.sp_start_job @job_name = ''' + @restoreJobName + N'''';
   PRINT N'	    IF (@retcode <> 0) BEGIN';
   PRINT N'	       PRINT N'''';';
   PRINT N'	       PRINT N''Error running ' + quotename(@restoreJobName) + N'. Rolling back...'';';
   PRINT N'	       ROLLBACK TRANSACTION;';
   PRINT N'	       RETURN;';
   PRINT N'	    END;';
   PRINT N'';

   --Check to make sure the transaction log tail backup was restored

   PRINT N'	--Make sure the Transaction Log Tail Backup was restored'
   PRINT N'';
   PRINT N'	IF (EXISTS(';
   PRINT N'	    SELECT TOP 1';
   PRINT N'	       *';
   PRINT N'	    FROM';
   PRINT N'	       msdb.dbo.backupset AS b';
   PRINT N'	    WHERE';
   PRINT N'	       b.database_name = ''' + @databaseName + N''''; 
   PRINT N'	       AND b.name LIKE ''' + @tailBackupName + N''''; 
   PRINT N'	    ORDER BY';
   PRINT N'	       backup_set_id DESC';
   PRINT N'	    ))';
   PRINT N'	BEGIN';
   PRINT N'	    COMMIT TRANSACTION;';
   PRINT N'	    PRINT N''Transaction Log Tail Backup successfully restored.'';';
   PRINT N'	END';
   PRINT N'	ELSE BEGIN';
   PRINT N'	    PRINT N'''';';
   PRINT N'	    PRINT N''' + quotename(@restoreJobName) + N' did not restore the Transaction Log Tail Backup. Rolling back...'';';
   PRINT N'	    ROLLBACK TRANSACTION;';
   PRINT N'	    RETURN;';
   PRINT N'	END;';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''An error was encountered while running/checking restore job' + quotename(@restoreJobName) + N'. Rolling Back and quitting execution...'';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N''
END;


SET @databaseName = N'';

PRINT N'--Now we restore the databases';
PRINT N'';

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE @databaseName < d.database_name))BEGIN

   SELECT TOP 1 
      @databaseName = d.database_name 
   FROM 
      @databases AS d 
   WHERE 
      @databaseName < d.database_name 
   ORDER BY 
      d.database_name ASC;

   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'    PRINT N''Bringing ' + quotename(@databaseName) + N' online'';';
   PRINT N'';
   PRINT N'    --Bring the database online. If the restore fails quit execution with error';
   PRINT N'';
   PRINT N'    RESTORE DATABASE ' + quotename(@databaseName) + N' WITH RECOVERY;'
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N''Error encountered while restoring ' + quotename(@databaseName) + N'. Quitting execution...'';';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';
END;

PRINT N'PRINT N''*****Failover to ' + quotename(@@SERVERNAME) + N' complete. Begin failover logshipping if necessary*****'';';

--End of script, begin failover logshipping if necessary


