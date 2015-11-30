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
  ,backup_job_id    uniqueidentifier null
);
insert into @databases (
   database_name
  ,secondary_id
  ,copy_job_id
  ,restore_job_id
  ,backup_job_id
)
select
   lssd.secondary_database as database_name, lssd.secondary_id as secondary_id, lss.copy_job_id, lss.restore_job_id, lspd.backup_job_id as backup_job_id
from
   msdb.dbo.log_shipping_secondary_databases AS lssd 
   LEFT JOIN sys.databases AS d ON (lssd.secondary_database = d.name)
   LEFT JOIN msdb.dbo.log_shipping_secondary AS lss  ON (lssd.secondary_id = lss.secondary_id)
   LEFT JOIN msdb.dbo.log_shipping_primary_databases AS lspd ON (lssd.secondary_database = lspd.primary_database)
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

IF NOT EXISTS(SELECT * FROM @databases)BEGIN
   PRINT N'There are no selected databases configured for logshipping as a secondary database, online, and restored. Quitting execution...';
   RETURN;
END;

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
    LEFT JOIN msdb.dbo.sysjobs AS sj ON (td.copy_job_id = sj.job_id OR td.restore_job_id = sj.job_id OR td.backup_job_id = sj.job_id) 
    LEFT JOIN msdb.dbo.sysjobhistory AS sjh ON (sjh.job_id = sj.job_id)
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

WHERE sjh.step_id = 0 
      AND (d.state_desc = N'ONLINE')
      AND ((@databaseFilter is null) OR (d.name like N'%' + @databaseFilter + N'%'))
      

GROUP BY sj.job_id;


IF (@debug = 1) BEGIN

   SELECT * FROM @jobs AS ji ORDER BY job_name;

END;


--================================

DECLARE @databaseName     nvarchar(128)
       ,@secondaryID      nvarchar(60)
       ,@copyJobName      nvarchar(128)
       ,@restoreJobName   nvarchar(128)
       ,@backupJobName    nvarchar(128)
       ,@tailBackupName   nvarchar(128) --Used to ensure that the copy/restore jobs successfully apply the transaction log tail backup to their respective databases 
       ,@maxlenDB         int
       ,@maxlenJob        int

SET @databaseName = N'';
SET @tailBackupName = N'%Transaction Log Tail Backup';
SET @maxlenDB = (select max(datalength(j.target_database)) from @jobs as j);
SET @maxlenJob = (select max(datalength(j.job_name)) from @jobs as j);

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Use the following script to failover to the following databases on ' + quotename(@@servername) + N', disabling their secondary instance jobs' + ':';
PRINT N'-- Run on the original secondary';
PRINT N'--';

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@copyJobName = j.job_name 
     ,@restoreJobName = j2.job_name 
   FROM
      @databases AS d LEFT JOIN @jobs AS j ON (d.copy_job_id = j.job_id)
      LEFT JOIN @jobs as j2 ON (d.restore_job_id = j2.job_id)

   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT N'-- ' + LEFT(quotename(@databaseName) + REPLICATE(N' ', @maxlenDB / 2), @maxlenDB / 2) + N'    ' + LEFT(quotename(@copyJobName) + REPLICATE(N' ', @maxlenJob / 2), @maxlenJob / 2) + N'    ' + quotename(@restoreJobName) ;

END;     

PRINT N'--';
PRINT N'-- And enabling the following backup jobs (if a database is already configured as a logshipping primary):';
PRINT N'--';

set @databaseName = N'';

raiserror('',0,1) WITH NOWAIT; --flush print buffer

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName AND d.backup_job_id IS NOT NULL) BEGIN

   SELECT TOP 1
       @databaseName = d.database_name
      ,@backupJobName = j.job_name
   FROM
      @databases AS d LEFT JOIN @jobs AS j ON (d.backup_job_id = j.job_id)

   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT N'-- ' + quotename(@backupJobName)

END;    

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
PRINT N'';

PRINT N'USE msdb';
PRINT N'';
PRINT N'SET nocount, arithabort, xact_abort on';
PRINT N'';
PRINT N'GO';
PRINT N'';
PRINT N'--#backupInfo takes result of RESTORE HEADERONLY to ensure Transaction Log Tail Backup is copied over';
PRINT N'';
PRINT N'--Drop the table if it exists';
PRINT N'';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#backupInfo'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #backupInfo';
PRINT N'';
PRINT N'CREATE TABLE #backupInfo (BackupName nvarchar(128),';
PRINT N' 						BackupDescription nvarchar(255),';
PRINT N' 						BackupType smallint,';
PRINT N' 						ExpirationDate datetime,';
PRINT N' 						Compressed tinyint,';
PRINT N' 						Position smallint,';
PRINT N' 						DeviceType tinyint,';
PRINT N' 						UserName nvarchar(128),';
PRINT N' 						ServerName nvarchar(128),';
PRINT N' 						DatabaseName nvarchar(128),';
PRINT N' 						DatabaseVersion int,';
PRINT N' 						DatabaseCreationDate datetime,';
PRINT N' 						BackupSize numeric(20, 0),';
PRINT N' 						FirstLSN numeric(25, 0),';
PRINT N' 						LastLSN numeric(25, 0),';
PRINT N' 						CheckpointLSN numeric(25, 0),';
PRINT N' 						DatabaseBackupLSN numeric(25, 0),';
PRINT N' 						BackupStartDate datetime,';
PRINT N' 						BackupFinishDate datetime,';
PRINT N' 						SortOrder smallint,';
PRINT N' 						[CodePage] smallint,';
PRINT N' 						UnicodeLocaleId int,';
PRINT N' 						UnicodeComparisonStyle int,';
PRINT N' 						CompatibilityLevel tinyint,';
PRINT N' 						SoftwareVendorId int,';
PRINT N' 						SoftwareVersionMajor int,';
PRINT N' 						SoftwareVersionMinor int,';
PRINT N' 						SoftwareVersionBuild int,';
PRINT N' 						MachineName nvarchar(128),';
PRINT N' 						Flags int,';
PRINT N' 						BindingId uniqueidentifier,';
PRINT N' 						RecoveryForkId uniqueidentifier,';
PRINT N' 						Collation nvarchar(128),';
PRINT N' 						FamilyGUID uniqueidentifier,';
PRINT N' 						HasBulkLoggedData bit,';
PRINT N' 						IsSnapshot bit,';
PRINT N' 						IsReadOnly bit,';
PRINT N' 						IsSingleUser bit,';
PRINT N' 						HasBackupChecksums bit,';
PRINT N' 						IsDamaged bit,';
PRINT N' 						BeginsLogChain bit,';
PRINT N' 						HasIncompleteMetaData bit,';
PRINT N' 						IsForceOffline bit,';
PRINT N' 						IsCopyOnly bit,';
PRINT N' 						FirstRecoveryForkID uniqueidentifier,';
PRINT N' 						ForkPointLSN numeric(25, 0),';
PRINT N' 						RecoveryModel nvarchar(60),';
PRINT N' 						DifferentialBaseLSN numeric(25, 0),';
PRINT N' 						DifferentialBaseGUID uniqueidentifier,';
PRINT N' 						BackupTypeDescription nvarchar(60),';
PRINT N' 						BackupSetGUID uniqueidentifier';
PRINT N')';
PRINT N'';
PRINT N'--#jobInfo takes the result of the sp xp_slqagent_enum_jobs';
PRINT N'-- xp_slqagent_enum_jobs is useful as it returns the ''running'' column which is how we''ll determine if a job is running';
PRINT N'';
PRINT N'--Drop the table if it exists';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#jobInfo'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #jobInfo';
PRINT N'';
PRINT N'CREATE TABLE #jobInfo (job_id                UNIQUEIDENTIFIER NOT NULL,';
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
PRINT N'                         job_state             INT              NOT NULL';
PRINT N')';
PRINT N'';   
PRINT N'';
PRINT N'PRINT N''Starting failover to secondary databases. Disabling secondary jobs...'';';
PRINT N'PRINT N'''';';
PRINT N''; 

raiserror('',0,1) WITH NOWAIT; --flush print buffer

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
   
   IF (@jobName LIKE N'%Backup%')BEGIN

      PRINT N'';
      PRINT N'    PRINT N''================================'';';
      PRINT N'	   PRINT N''Enabling backup job ' + quotename(@jobName) + N''';';
      PRINT N'';
      PRINT N'	   EXEC @retcode = msdb.dbo.sp_update_job @job_name = ''' + @jobName + N''', @enabled = 1';
      PRINT N'	      IF(@retcode = 1) ';
      PRINT N'	         BEGIN';
      PRINT N'	            PRINT N''Error enabling ' + quotename(@jobName) + N'. Rolling back and quitting batch execution...'';';
      PRINT N'	            ROLLBACK TRANSACTION;';
      PRINT N'	            RETURN;';
      PRINT N'	         END';
      PRINT N'	      ELSE';
      PRINT N'	         COMMIT TRANSACTION;';
      PRINT N'	         PRINT N''' + quotename(@jobName) + N' enabled successfully'';';
      PRINT N'	         PRINT N'''';';
      PRINT N'';

   END
   ELSE BEGIN
      PRINT N'';
      PRINT N'    PRINT N''================================'';';
      PRINT N'    PRINT N''Disabling ' + quotename(@jobName) + N''';';
      PRINT N'';
      PRINT N'    --We Make sure the jobs aren''t running to avoid issuse with premature cancelation since they''re cmd commands';
      PRINT N'	';
      PRINT N'    DELETE FROM #jobInfo';
      PRINT N'	   INSERT INTO #jobInfo';
      PRINT N'	   EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
      PRINT N'	';
      PRINT N'	   WHILE EXISTS (SELECT * FROM #jobInfo as ji WHERE ji.job_id = ''' + @jobID + N''' AND ji.running <> 0)';
      PRINT N'	   BEGIN';
      PRINT N'	      PRINT N''Waiting ' + @avgRuntime + N' for job to finish running' + N''';';
      PRINT N'	      WAITFOR DELAY ' + N'''' + @avgRuntime + N'''';
      PRINT N'	';
      PRINT N'	      DELETE FROM #jobInfo';
      PRINT N'	      INSERT INTO #jobInfo';
      PRINT N'	      EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
      PRINT N'	   END;';
      PRINT N'	';

   --Attempting to disable a job that is already disabled is not an issue
      
      PRINT N'	   EXEC @retcode = msdb.dbo.sp_update_job @job_name = ''' + @jobName + N''', @enabled = 0';
      PRINT N'	    IF(@retcode = 1) ';
      PRINT N'	       BEGIN';
      PRINT N'	          --You''ll notice these empty print statements before error messages, they are a workaround for print messages not being outputted';
      PRINT N'	          --when a rollback is performed after them. Not sure why it happens, but others have experienced this as well';
      PRINT N'	          PRINT N'''';';
      PRINT N'	          PRINT N''Error disabling ' + quotename(@jobName) + N' Rolling back...'';';
      PRINT N'	          ROLLBACK TRANSACTION;';
      PRINT N'	          RETURN;';
      PRINT N'	       END';
      PRINT N'	       ELSE BEGIN';
      PRINT N'	          COMMIT TRANSACTION;'
      PRINT N'	          PRINT N''Job disabled successfully'';';
      PRINT N'	          PRINT N'''';';
      PRINT N'	       END;';
      PRINT N'';
   END;

   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''There was an error while working on ' + quotename(@jobName) + N'. Rolling back and quitting batch execution...'';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';

   raiserror('',0,1) WITH NOWAIT; --flush print buffer
END;

PRINT N'';
PRINT N'PRINT N''Running databases'''' secondary jobs to ensure their respective transaction log tail backups are applied...'';';
PRINT N'PRINT N'''';';
PRINT N'';

set @databaseName = N'';

--Iterate through the databases, running their jobs and then restoring them

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@secondaryID = d.secondary_id
     ,@copyJobName = j.job_name     
     ,@restoreJobName = j2.job_name 
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
   PRINT N'PRINT N''=================================='';';
   PRINT N'PRINT N''Running jobs for ' + quotename(@databaseName) + N'. Starting copy job...'';';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'BEGIN TRY';
   PRINT N''
   PRINT N'    DECLARE @retcode int';
   PRINT N'           ,@lastCopiedFile     nvarchar(500)';
   PRINT N'           ,@currentCopiedFile  nvarchar(500)';
   PRINT N'           ,@backupInfoCommand  nvarchar(1100)';
   PRINT N'           ,@start              datetime -- for getting the overlapsed time and filtering MHD';
   PRINT N'           ,@stop               datetime -- for getting the overlapsed time';
   PRINT N'           ,@beforeLogCount     nvarchar(10) -- for the count(*) of MHD before the jobs are run';
   PRINT N'           ,@afterLogCount      nvarchar(10) -- for the count(*) of MHD after the jobs are run';
   PRINT N'';
   PRINT N' -- Start preparing for the check to ensure the log tail is copied over';
   PRINT N'';
   PRINT N'	SELECT';
   PRINT N'	    @lastCopiedFile = lss.last_copied_file';
   PRINT N'	FROM';
   PRINT N'	    log_shipping_secondary AS lss';
   PRINT N'	WHERE';
   PRINT N'	    lss.secondary_id = ''' + @secondaryID + N''';';
   PRINT N'';
   PRINT N'	-- get the initial count(*) for MHD';
   PRINT N'';
   PRINT N'	select ';
   PRINT N'	   @beforeLogCount = Count(*)';
   PRINT N'	from ';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N''
   PRINT N'    -- Start timer for copy job test';
   PRINT N'';
   PRINT N'	SET @start = current_timestamp';
   PRINT N''
   PRINT N'    --Start the copy job';
   PRINT N'';
   PRINT N'	EXEC @retcode = msdb.dbo.sp_start_job @job_name = ''' + @copyJobName + N'''';
   PRINT N'	    IF(@retcode <> 0) BEGIN';
   PRINT N'	       PRINT N'''';';
   PRINT N'	       PRINT N''Error running ' + quotename(@copyJobName) + N'. Rolling back...'';';
   PRINT N'           PRINT N'''';';
   PRINT N'	       ROLLBACK TRANSACTION;';
   PRINT N'	       RETURN;';
   PRINT N'	    END';
   PRINT N'        ELSE BEGIN';
   PRINT N'           PRINT N''Copy job started successfully. Starting check to ensure log backup tail was copied over...'';';
   PRINT N'        END;';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''Error running ' + quotename(@copyJobName) + N'. Rolling back...'';';
   PRINT N'    PRINT N'''';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN';
   PRINT N'END CATCH;';
   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'	--Start check to make sure the transaction log tail backup was copied';
   PRINT N'';
   PRINT N'	-- get the current count(*) for MHD';
   PRINT N'';
   PRINT N'	SELECT';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	FROM';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	PRINT N''right after: '' + @afterLogCount;'; --testing
   PRINT N'';
   PRINT N'	-- wait for MHD to get updated';
   PRINT N'';
   PRINT N'	WHILE(@afterLogCount = @beforeLogCount)BEGIN';
   PRINT N'';
   PRINT N'	   SELECT';
   PRINT N'	      @afterLogCount = Count(*)';
   PRINT N'	   FROM';
   PRINT N'	      log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	   PRINT N''during: '' + @afterLogCount;'; --testing
   PRINT N'';
   PRINT N'	   WAITFOR DELAY ''00:00:1'';';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	DECLARE @session varchar';
   PRINT N'	       ,@numCopied nvarchar(128)';
   PRINT N'	       ,@message nvarchar(4000)';
   PRINT N'';
   PRINT N'	-- Wait for all of the rows to be inserted into MHD from the copy job''s run';
   PRINT N'';
   PRINT N'	SELECT TOP 1 @session = session_status FROM log_shipping_monitor_history_detail ORDER BY log_time desc';
   PRINT N'';
   PRINT N'	WHILE(@session = 0 or @session = 1)BEGIN -- 0 = starting, 1 = running';
   PRINT N'';
   PRINT N'	   PRINT N''session: '' + @session'; --testing
   PRINT N'';
   PRINT N'	   WAITFOR DELAY ''00:00:1'' -- Makes it so the output for the above print isn''t too long';
   PRINT N'';
   PRINT N'	   SELECT TOP 1 @session = session_status FROM log_shipping_monitor_history_detail ORDER BY log_time desc';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	--getting the final count(*) just to make sure the previous worked correctly'; --testing
   PRINT N'';
   PRINT N'	select';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	from';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	PRINT N''finished: '' + @afterLogCount';
   PRINT N'';
   PRINT N'    --Output the elapsed time';
   PRINT N'';
   PRINT N'	SET @stop = current_timestamp';
   PRINT N'	PRINT DATEDIFF(s, @start, @stop)';
   PRINT N'';
   PRINT N'	--Determine if the copy job copied over anything';
   PRINT N'';
   PRINT N'	IF(@session = 2)BEGIN --If not 2, then the job did not run successfully';
   PRINT N'';
   PRINT N'	   SELECT TOP 1 ';
   PRINT N'	      @message = rtrim(l.message)';
   PRINT N'	   FROM ';
   PRINT N'	      log_shipping_monitor_history_detail as l';
   PRINT N'	   ORDER BY log_time desc';
   PRINT N'';
   PRINT N'	   -- We''re starting at the right side of the message taking one char at a time and checking the ascii value until we don''t get a number in order to get the entire number';
   PRINT N'';
   PRINT N'	   DECLARE @index int';
   PRINT N'	          ,@temp char;';
   PRINT N'';
   PRINT N'	   SET @index = datalength(@message) / 2;';
   PRINT N'	   SET @temp = substring(@message, @index, 1)';
   PRINT N'	   SET @numCopied = '''';';
   PRINT N'';
   PRINT N'	   WHILE(ascii(@temp) > 47 and ascii(@temp) < 58)BEGIN';
   PRINT N'';
   PRINT N'	      SET @numCopied = @temp + @numCopied --append the new number to @numCopied';
   PRINT N'	      SET @index = @index - 1;';
   PRINT N'	      SET @temp = substring(@message, @index, 1)';
   PRINT N'';
   PRINT N'	   END;';
   PRINT N'';
   PRINT N'	   PRINT N'' Number of files copied: '' + @numCopied;'; -- testing
   PRINT N'';
   PRINT N'	END';
   PRINT N'	ELSE BEGIN';
   PRINT N'	   PRINT N'''';';
   PRINT N'	   PRINT N''Error running ' + quotename(@copyJobName) + N'. Rolling back...'';';
   PRINT N'       PRINT N'''';';
   PRINT N'	   ROLLBACK TRANSACTION;';   
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	IF(CAST(@numCopied as INT) > 0)BEGIN';    
   PRINT N''; 
   PRINT N'	   SELECT';
   PRINT N'		    @currentCopiedFile = lss.last_copied_file';
   PRINT N'	   FROM';
   PRINT N'		    log_shipping_secondary AS lss';
   PRINT N'	   WHERE';
   PRINT N'		    lss.secondary_id = ''' + @secondaryID + N''';';
   PRINT N'';
   PRINT N'	    -- We make sure that log_shipping_secondary has updated';
   PRINT N''
   PRINT N'	   WHILE(@lastCopiedFile = @currentCopiedFile)BEGIN';
   PRINT N'';
   PRINT N'	       PRINT N''Waiting for log_shipping_secondary to update last_copied_file...'';';
   PRINT N'	       WAITFOR DELAY ''00:00:1'';';
   PRINT N'		   SELECT';
   PRINT N'		      @currentCopiedFile = lss.last_copied_file';
   PRINT N'		   FROM';
   PRINT N'		      log_shipping_secondary AS lss';
   PRINT N'		   WHERE';
   PRINT N'		      lss.secondary_id = ''' + @secondaryID + N''';';
   PRINT N'	    END';
   PRINT N'';
   PRINT N'	    --Now we make sure the file is the the log tail backup';
   PRINT N'';
   PRINT N'	    SET @backupInfoCommand = N''RESTORE HEADERONLY FROM DISK = N'''''' + @currentCopiedFile + N'''''''''; 
   PRINT N'';
   PRINT N'	    DELETE FROM #backupInfo';
   PRINT N'	    INSERT INTO #backupInfo('
   PRINT N'			 BackupName,';
   PRINT N'			 BackupDescription,';
   PRINT N'			 BackupType,';
   PRINT N'			 ExpirationDate,';
   PRINT N'			 Compressed,';
   PRINT N'			 Position,';
   PRINT N'			 DeviceType,';
   PRINT N'			 UserName,';
   PRINT N'			 ServerName,';
   PRINT N'			 DatabaseName,';
   PRINT N'			 DatabaseVersion,';
   PRINT N'			 DatabaseCreationDate,';
   PRINT N'			 BackupSize,';
   PRINT N'			 FirstLSN,';
   PRINT N'			 LastLSN,';
   PRINT N'			 CheckpointLSN,';
   PRINT N'			 DatabaseBackupLSN,';
   PRINT N'			 BackupStartDate,';
   PRINT N'			 BackupFinishDate,';
   PRINT N'			 SortOrder,';
   PRINT N'			 [CodePage],';
   PRINT N'			 UnicodeLocaleId,';
   PRINT N'			 UnicodeComparisonStyle,';
   PRINT N'			 CompatibilityLevel,';
   PRINT N'			 SoftwareVendorId,';
   PRINT N'			 SoftwareVersionMajor,';
   PRINT N'			 SoftwareVersionMinor,';
   PRINT N'			 SoftwareVersionBuild,';
   PRINT N'			 MachineName,';
   PRINT N'			 Flags,';
   PRINT N'			 BindingId,';
   PRINT N'			 RecoveryForkId,';
   PRINT N'			 Collation,';
   PRINT N'			 FamilyGUID,';
   PRINT N'			 HasBulkLoggedData,';
   PRINT N'			 IsSnapshot,';
   PRINT N'			 IsReadOnly,';
   PRINT N'			 IsSingleUser,';
   PRINT N'			 HasBackupChecksums,';
   PRINT N'			 IsDamaged,';
   PRINT N'			 BeginsLogChain,';
   PRINT N'			 HasIncompleteMetaData,';
   PRINT N'			 IsForceOffline,';
   PRINT N'			 IsCopyOnly,';
   PRINT N'			 FirstRecoveryForkID,';
   PRINT N'			 ForkPointLSN,';
   PRINT N'			 RecoveryModel,';
   PRINT N'			 DifferentialBaseLSN,';
   PRINT N'			 DifferentialBaseGUID,';
   PRINT N'			 BackupTypeDescription,';
   PRINT N'			 BackupSetGUID ';
   PRINT N'		)'
   PRINT N'		EXEC sp_executesql @backupInfoCommand';
   PRINT N'';
   PRINT N'		IF(EXISTS(SELECT * FROM #backupInfo AS bi WHERE bi.backupName LIKE ''' + @tailBackupName + N'''))BEGIN';
   PRINT N'	         PRINT N'''';';
   PRINT N'		    PRINT N''Copy job successfully copied the Transaction Log Tail Backup. Starting restore job...'';';
   PRINT N'	         PRINT N'''';';
   PRINT N'		    DELETE FROM #backupInfo;';
   PRINT N'		END';
   PRINT N'		ELSE BEGIN';
   PRINT N'		    PRINT N'''';';
   PRINT N'	         PRINT N'''';';
   PRINT N'		    PRINT N''' + quotename(@copyJobName) + N' did not copy over the Transaction Log Tail Backup. Check to make sure the file name follows the same format'';';
   PRINT N'		    PRINT N''as the backups output by the jobs themselves. This includes being in UTC. Rolling Back and quitting execution...'';';
   PRINT N'	         PRINT N'''';';
   PRINT N'		    ROLLBACK TRANSACTION;';
   PRINT N'		    RETURN;';
   PRINT N'		END;';
   PRINT N'    END';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''There was an issue while checking to make sure the transaction log was copied over. Rolling back and quitting batch execution.'';';
   PRINT N'    PRINT N'''';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';

   --Check to make sure the transaction log tail backup was restored

   --TODO:

   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'    --Run restore job';
   PRINT N'';
   PRINT N'	EXEC @retcode = msdb.dbo.sp_start_job @job_name = ''' + @restoreJobName + N'''';
   PRINT N'	    IF (@retcode <> 0) BEGIN';
   PRINT N'	 	    PRINT N'''';';
   PRINT N'	 	    PRINT N''Error running ' + quotename(@restoreJobName) + N'. Rolling back...'';';
   PRINT N'             PRINT N'''';';
   PRINT N'	 	    ROLLBACK TRANSACTION;';
   PRINT N'	 	    RETURN;';
   PRINT N'        END;'
   PRINT N'    --Make sure the Transaction Log Tail Backup was restored'
   PRINT N'';
   PRINT N'	IF (EXISTS(';
   PRINT N'	   SELECT';
   PRINT N'	 	 *';
   PRINT N'	   FROM';
   PRINT N'	 	 log_shipping_secondary_databases AS lssd';
   PRINT N'          INNER JOIN log_shipping_secondary as lss ON (lssd.last_restored_file = lss.last_copied_file)';
   PRINT N'	   WHERE';
   PRINT N'	 	 lssd.secondary_database = ''' + @databaseName + N''''; 
   PRINT N'	   ))';
   PRINT N'	BEGIN';
   PRINT N'	   PRINT N''Transaction Log Tail Backup successfully restored.'';';
   PRINT N'       PRINT N'''';';
   PRINT N'	   COMMIT TRANSACTION;';
   PRINT N'	END';
   PRINT N'	ELSE BEGIN';
   PRINT N'	   PRINT N'''';';
   PRINT N'	   PRINT N''' + quotename(@restoreJobName) + N' did not restore the Transaction Log Tail Backup. Rolling back...'';';
   PRINT N'	   PRINT N'''';';
   PRINT N'	   ROLLBACK TRANSACTION;';
   PRINT N'	   RETURN;';
   PRINT N'	END;';   
   PRINT N'';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''And error was encountered while checking if ' + quotename(@restoreJobName) + N' restored the Transaction Tail Log Backup. Rolling Back and quitting batch execution...'';';
   PRINT N'	PRINT N'''';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';
   
   raiserror('',0,1) WITH NOWAIT; --flush print buffer
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
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''=================================='';';
   PRINT N'    PRINT N''Bringing ' + quotename(@databaseName) + N' online'';';
   PRINT N'';
   PRINT N'    --Bring the database online. If the restore fails quit execution with error';
   PRINT N'';
   PRINT N'    RESTORE DATABASE ' + quotename(@databaseName) + N' WITH RECOVERY;'
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N''Error encountered while restoring ' + quotename(@databaseName) + N'. Quitting execution...'';';
   PRINT N'    PRINT N'''';';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';

   raiserror('',0,1) WITH NOWAIT; --flush print buffer
END;


PRINT N'DROP TABLE #backupInfo, #jobInfo';
PRINT N'PRINT N''*****Failover to ' + quotename(@@SERVERNAME) + N' complete. Begin failover logshipping if necessary*****'';';

--End of script, begin failover logshipping if necessary

