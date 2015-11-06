/*

Run this on the original primary server
Use this script to produce a T-SQL script to failover all of the online logshipped databases on current server, matching filters, to the backup location specified 
during their logshipping configurations

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
--Instead of using the registry to find the backup we'll use msdb.dbo.log_shipping_primary_databases, which also functions as the check
--to make sure the db is logshipped
--

SELECT top 1
   @backupFilePath = backup_directory
FROM msdb.dbo.log_shipping_primary_databases
;

if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';

declare @backup_files table (
   database_name    nvarchar(128) not null primary key clustered
 , backup_file_name nvarchar(260)
 , standby_file_name nvarchar(260)
);

insert into @backup_files (
   database_name
 , backup_file_name
 , standby_file_name
)
--Changed the format of {backupTime} to include milliseconds so it will fit the formatting of the other logshipping files
--After some testing I found that it is in fact necessary to have the formatting this way. A .trn file that left out the seconds and milliseconds was not
--found by the secondary copy job. A later backup with the necessary seconds and milliseconds was found, however. This may be due to the restore job using the datetime
--as logging information
select
   pd.primary_database      as database_name
 , replace(replace(replace(
      N'{backup_path}{database_name}_{backupTime}.trn'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', pd.primary_database)
    , N'{backupTime}', replace(replace(replace(replace(convert(nvarchar(19), GETUTCDATE(), 121), N'-', N''), N':', N''),N'.', N''), N' ', N'')) AS backup_file_name
, replace(replace(replace(
      N'{backup_path}{database_name}_{backupTime}.ldf'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', pd.primary_database)
    , N'{backupTime}', replace(replace(replace(replace(convert(nvarchar(19), GETUTCDATE(), 121), N'-', N''), N':', N''),N'.', N''), N' ', N'')) AS standby_file_name
from
   msdb.dbo.log_shipping_primary_databases AS pd left JOIN sys.databases as d ON (pd.primary_database = d.name)
--
--We don't want to make backups if a db is offline, a system db,  or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   and ((@exclude_system = 0)
      or (d.name not in (N'master', N'model', N'msdb')))
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
   and (d.name <> N'tempdb')
                                                  
order by
   d.name;

IF NOT EXISTS(SELECT * FROM @backup_files)
   PRINT N'There are no databases configured for logshipping as a primary database';

select
   @databaseFilter as DatabaseFilter
 , @backupFilePath as BackupFilePath
 , @exclude_system as ExcludeSystemDatabases;

if (@debug = 1) begin

   select
      *
   from
      @backup_files as bf
   order by
      bf.database_name;

end;

--@jobs is used to stop all backup jobs on the server
--ID is used to that the table can be stepped through later
--We don't include this information in @backup_files because that would imply 1 job for each database, where in the secondary instance a database has 2 jobs assigned to it

DECLARE @jobs TABLE (
   job_id         uniqueidentifier NOT NULL PRIMARY KEY
  ,job_name       nvarchar(128) NOT NULL
  ,avg_runtime    int NOT NULL --HHMMSS format
);

INSERT INTO @jobs (
  job_id
 ,job_name
 ,avg_runtime
)
SELECT 
       sj.job_id AS job_id, MAX(sj.name), AVG(t2.Total_Seconds) AS avg_runtime
FROM
    @backup_files AS bf 
    LEFT JOIN msdb.dbo.log_shipping_primary_databases AS lspd ON (lspd.primary_database = bf.database_name) --We join to @backup_files in case we have a filter on a logshipped db
    LEFT JOIN msdb.dbo.log_shipping_secondary_databases AS lssd ON (lssd.secondary_database = bf.database_name)
    LEFT JOIN msdb.dbo.log_shipping_secondary AS lss ON (lss.secondary_id = lssd.secondary_id)
    LEFT JOIN msdb.dbo.sysjobs AS sj ON (lspd.backup_job_id = sj.job_id OR lss.copy_job_id = sj.job_id OR lss.restore_job_id = sj.job_id) 
    RIGHT JOIN msdb.dbo.sysjobhistory AS sjh ON (sjh.job_id = lspd.backup_job_id OR sjh.job_id = lss.copy_job_id OR sjh.job_id = lss.restore_job_id ) --We don't need the avg_runtime for the secondary jobs but it makes it so the backups are forced to have a non-null value
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
   
GROUP BY sj.job_id;


IF (@debug = 1) BEGIN

   SELECT * FROM @jobs AS ji ORDER BY ji.job_name

END;
   

--================================

print N'--================================';
print N'--';
print N'-- Use the following script to perform a logshipping failover/failback for the following databases on ' + quotename(@@servername) + ':';
print N'-- Run on the original primary
print N'--';

declare @databaseName   nvarchar(128)
      , @backupFileName nvarchar(260)
      , @standbyFileName nvarchar(260)
      , @maxLen         int
      , @backupJobID    uniqueidentifier
      , @jobName        nvarchar(128)
      , @totalSeconds   int
      , @avgRuntime     nvarchar(8);

set @maxLen = (select max(datalength(bf.database_name)) from @backup_files as bf);
set @databaseName = N'';

while exists(select * from @backup_files as bf where bf.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = bf.backup_file_name
   from
      @backup_files as bf
   where
      (bf.database_name > @databaseName)
   order by
      bf.database_name;

   print N'--    ' + left(@databaseName + replicate(N' ', @maxLen / 2), @maxLen / 2) + N'   ' + @backupFileName;
end;

PRINT N'--';
PRINT N'-- Disabling the following jobs:';
PRINT N'--';

set @jobName = N'';

WHILE EXISTS(SELECT * FROM @jobs AS j WHERE j.job_name > @jobName AND j.job_name LIKE '%Backup%') BEGIN

   SELECT TOP 1
      @jobName = j.job_name
   FROM
      @jobs as j
   WHERE
      j.job_name > @jobName 
      AND j.job_name LIKE '%Backup%'
   ORDER BY 
      j.job_name;

   PRINT N'--   ' + @jobName;

END;

PRINT N'--';
PRINT N'-- And enabling the following jobs (for primaries already configured as failover secondaries):';
PRINT N'--';

set @jobName = N'';

WHILE EXISTS(SELECT * FROM @jobs AS j WHERE j.job_name > @jobName AND j.job_name NOT LIKE '%Backup') BEGIN

   SELECT TOP 1
      @jobName = j.job_name
   FROM
      @jobs as j
   WHERE
      j.job_name > @jobName 
      AND j.job_name NOT LIKE '%Backup%'
   ORDER BY 
      j.job_name;

   PRINT N'--   ' + @jobName;

END;

print N'--';
print N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
print N'--';
print N'--================================';

print N'';
print N'USE [master];';
print N'GO';
PRINT N'';
PRINT N'--#jobInfo takes the result of the sp xp_slqagent_enum_jobs';
PRINT N'--xp_slqagent_enum_jobs is useful as it returns the ''running'' column which is how we''ll determine if a job is running';
PRINT N'';
PRINT N'DECLARE #jobInfo TABLE (job_id                UNIQUEIDENTIFIER NOT NULL,';
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

--Iterate through the job ids and generate scripts to disable backup jobs and enable secondary jobs if failover logshipping has already been configured

set @jobName = N'';

WHILE EXISTS (SELECT * FROM @jobs AS j WHERE @jobName < j.job_name) BEGIN

   SELECT TOP 1
   @jobName = j.job_name
  ,@backupJobID = j.job_id
  ,@totalSeconds = j.avg_runtime
   FROM 
      @jobs AS j
   WHERE 
      (j.job_name > @jobName)
   ORDER BY
      j.job_name;

   --Convert the int avg_runtime to a datetime format acceptable by WAITFOR DELAY

   SET @avgRuntime = CAST((@totalSeconds / 3600) AS nvarchar(2)) + ':' + CAST((@totalSeconds / 60 % 60) AS nvarchar(2)) + ':' + CAST((@totalSeconds % 60) AS nvarchar(2)) 
   
   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'DECLARE @retCode int';

   IF(@jobName LIKE '%Backup%')BEGIN
      
      PRINT N'';
      PRINT N'	PRINT N''================================'';';
      PRINT N'	PRINT N''Disabling Logshipping backup job ' + quotename(@jobName) + N''';';
      PRINT N'';
      PRINT N'';
      PRINT N'	--We Make sure the jobs aren''t running to avoid issuse with premature cancelation';
      PRINT N'';
      PRINT N'	INSERT INTO #jobInfo';
      PRINT N'	EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
      PRINT N'';
      PRINT N'	WHILE EXISTS (SELECT * FROM #jobInfo as ji WHERE ji.job_id = ' + REPLACE(REPLACE(quotename(@backupJobID), '[', ''''), ']', '''') + N' AND ji.running <> 0)';
      PRINT N'	BEGIN';
      PRINT N'	    PRINT N''Waiting ' + @avgRuntime + N' for job to finish running' + N''';';
      PRINT N'	    WAITFOR DELAY ' + N'''' + @avgRuntime + N'''';
      PRINT N'';
      PRINT N'	    DELETE FROM #jobInfo';
      PRINT N'	    INSERT INTO #jobInfo';
      PRINT N'	    EXEC xp_sqlagent_enum_jobs 1, ''dbo''';
      PRINT N'	END;';
      PRINT N'';
      PRINT N'	EXEC @retCode = msdb.dbo.sp_update_job @job_id = ' + REPLACE(REPLACE(quotename(@backupJobID), '[', ''''), ']', '''') + N', @enabled = 0';
      PRINT N'	    IF(@retCode = 1) ';
      PRINT N'	       BEGIN';
      PRINT N'	          PRINT N''Error running sp_update_job for ' + quotename(@jobName) + N'. Rolling back and quitting execution...'';';
      PRINT N'	          ROLLBACK TRANSACTION;';
      PRINT N'	          RETURN;';
      PRINT N'	       END';
      PRINT N'	    ELSE';
      PRINT N'	       COMMIT TRANSACTION;';
      PRINT N'	       PRINT N''' + quotename(@jobName) + N' disabled successfully'';';
      PRINT N'	       PRINT N'''';';
      PRINT N'';
   END
   ELSE BEGIN
      PRINT N'';
      PRINT N'	PRINT N''================================'';';
      PRINT N'	PRINT N''Enabling secondary job ' + quotename(@jobName) + N''';';
      PRINT N'';
      PRINT N'	EXEC @retCode = msdb.dbo.sp_update_job @job_id = ' + REPLACE(REPLACE(quotename(@backupJobID), '[', ''''), ']', '''') + N', @enabled = 1';
      PRINT N'	    IF(@retCode = 1) ';
      PRINT N'	       BEGIN';
      PRINT N'	          PRINT N''Error enabling ' + quotename(@jobName) + N'. Rolling back and quitting execution...'';';
      PRINT N'	          ROLLBACK TRANSACTION;';
      PRINT N'	          RETURN;';
      PRINT N'	       END';
      PRINT N'	    ELSE';
      PRINT N'	       COMMIT TRANSACTION;';
      PRINT N'	       PRINT N''' + quotename(@jobName) + N' enabled successfully'';';
      PRINT N'	       PRINT N'''';';
      PRINT N'';
   END;

   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''An error was encountered while working on ' + quotename(@jobName) + N'. Rolling back and quitting execution...';
   PRINT N'    ROLLBACK TRANSACTION';
   PRINT N'    RETURN';
   PRINT N'END CATCH;';

END;

PRINT N'';
PRINT N'PRINT N'''';';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''Starting failovers'';';
PRINT N'';
PRINT N'/*';
PRINT N'IMPORTANT: The name given to the Transaction Tail Log Backup file is used during the secondary instance script to identify it.'
PRINT N'If you change the name here, you''d have to it change within ''Expected Failover Script Generator Secondary Instance'' to reflect that'
PRINT N'If you do wish to change the name, I''d recommend keeping the name so that it can be identified by ''%Trasaction Log Tail Backup'' so that you don''t have to update the secondary script';
PRINT N'If doing so is absolutely necessary, the variable you need to update is @tailBackupName';
PRINT N'*/';

SET @databaseName = N'';

while exists(select * from @backup_files as bf where bf.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = replace(bf.backup_file_name, N'''', N'''''')
    , @standbyFileName = replace(bf.standby_file_name, N'''', N'''''')
   from
      @backup_files as bf
   where
      (bf.database_name > @databaseName)
   order by
      bf.database_name;

   PRINT N'GO'
   PRINT N'';
   PRINT N'PRINT N''================================'';';
   PRINT N'PRINT N''Starting Failover for ' + quotename(@databasename) + N' on ' + quotename(@@SERVERNAME) + N' at ' +  convert(nvarchar, current_timestamp, 120) + N' as ' + quotename(suser_sname()) +  N'...'';';
   PRINT N'';
   PRINT N'PRINT N''Backing up the tail of the transaction log to ' + quotename(@backupFileName) + N''';';
   PRINT N'PRINT N'''';';
   PRINT N'';
   PRINT N'--Make sure to read the comment in regards to changing the file name before doing so. (Search the file for ''IMPORTANT'')';
   PRINT N'';
   PRINT N'BACKUP LOG ' + quotename(@databasename) + N' TO DISK = N''' + REPLACE(REPLACE(quotename(@backupFileName), N'[',N''), N']', N'')  + N'''';
   PRINT N'WITH NO_TRUNCATE , NOFORMAT , NOINIT, NAME = N''' + quotename(@databasename) + N'-Transaction Log Tail Backup''' + N', ';
   PRINT N'SKIP, NOREWIND, NOUNLOAD, STANDBY = N''' + REPLACE(REPLACE(quotename(@standbyFileName), N'[',N''), N']', N'') + N''', STATS = 10';
   PRINT N'';
   PRINT N'PRINT N'''';';
   PRINT N'PRINT N''If the log backup was successful,  ' + quotename(@databasename) + N' is now in a Standby/Read-Only state.'';';
   PRINT N'PRINT N'''';';
   PRINT N'';
   PRINT N'';
  
end;

PRINT N'PRINT N''*****Failover completed, continue to Expected Failover Script Generator Secondary Instance*****'';';

--End of script, continue to secondary instance script