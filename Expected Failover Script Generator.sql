/*

Use this script to produce a T-SQL script to failover all of the online logshipped databases on current server, matching filters, to the backup location specified 
during their logshipping configurations

*/

set nocount on;
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
    , N'{backupTime}', replace(replace(replace(replace(convert(nvarchar(19), current_timestamp, 121), N'-', N''), N':', N''),N'.', N''), N' ', N'')) AS backup_file_name
, replace(replace(replace(
      N'{backup_path}{database_name}_{backupTime}.ldf'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', pd.primary_database)
    , N'{backupTime}', replace(replace(replace(replace(convert(nvarchar(19), current_timestamp, 121), N'-', N''), N':', N''),N'.', N''), N' ', N'')) AS standby_file_name
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

--@job_ids is used to stop all backup jobs on the server
--ID is used to that the table can be stepped through later

DECLARE @job_ids TABLE (
   ID             int identity (1,1) NOT NULL
  ,job_id         uniqueidentifier NOT NULL PRIMARY KEY
  ,avg_runtime    int NOT NULL 
);

INSERT INTO @jobs (
  job_id
 ,avg_runtime
)
SELECT 
       lspd.backup_job_id AS job_id, AVG(sjh.run_duration) AS avg_runtime
FROM
    msdb.dbo.log_shipping_primary_databases AS lspd 
    RIGHT JOIN @backup_files AS bf ON (lspd.primary_database = bf.database_name) --We join lspd in case we have a filter on a logshipped db
    LEFT JOIN msdb.dbo.sysjobhistory as sjh ON (sjh.job_id = lspd.backup_job_id)

WHERE sjh.step_id = 0
   
GROUP BY lspd.backup_job_id;


IF (@debug = 1) BEGIN

   SELECT * FROM @job_ids AS ji

END;
   

--================================

print N'--================================';
print N'--';
print N'-- Use the following script to perform a logship failback for the following databases on ' + quotename(@@servername) + ':';
print N'--';

declare @databaseName   nvarchar(128)
      , @backupFileName nvarchar(260)
      , @standbyFileName nvarchar(260)
      , @maxLen         int
      , @backupJobID    uniqueidentifier;

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

   print N'--    ' + left(@databaseName + replicate(N'', @maxLen / 2), @maxLen / 2) + N'   ' + @backupFileName;
end;

print N'--';

print N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
print N'--';
print N'--================================';

print N'';
print N'USE [master];';
print N'GO';


declare @cmd    nvarchar(max)
      , @fileID int
      , @idCounter int
      , @avgRuntime int
      , @avgRuntimeString nvarchar(8);


PRINT N'DECLARE @retCode int';
PRINT N'';
PRINT N'PRINT N''Beginning Transaction'';';
PRINT N'';
PRINT N'BEGIN TRANSACTION';
PRINT N'';
PRINT N'PRINT N''Disabling Logshipping backup jobs on ' + quotename(@@SERVERNAME) + N''';';
PRINT N'';

--Iterate through the backup job ids and disable them

set @idCounter = -1;

WHILE EXISTS (SELECT * FROM @jobs AS j WHERE j.ID > @idCounter) BEGIN

   SELECT TOP 1
   @idCounter = j.ID
  ,@backupJobID = j.job_id
  ,@avgRuntime = j.avg_runtme
   FROM 
      @jobs AS j
   WHERE 
      (j.ID > @idCounter);

   --Convert the int avg_runtime (in seconds) to a form acceptable by WAITFOR DELAY
   --@avgRuntime / 360 = #hours, % 24 keeps it under 24 so that it fits the datetime format. Similar behavior for hours and seconds

   SET @avgRuntimeString = CAST((@avgRuntime / 360 % 24) AS nvarchar(2)) + ':' + CAST((@avgRuntime / 60 % 60) AS nvarchar(2)) + ':' + CAST((@avgRuntime % 60) AS nvarchar(2))
   
   PRINT N'--Make sure the jobs aren''t running to avoid issuse with premature cancelation';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'';
   PRINT N'DECLARE @job_info TABLE (job_id                UNIQUEIDENTIFIER NOT NULL,';
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
   PRINT N'INSERT INTO @job_info';
   PRINT N'EXEC xp_slqagent_enum_jobs 1, ''dbo''';
   PRINT N'';
   PRINT N'WHILE EXISTS (SELECT * FROM @job_info as ji WHERE ji.job_id = ' + quotename(@backupJobID) + N' AND ji.running <> 0)';
   PRINT N'BEGIN';
   PRINT N'    WAITFOR DELAY ' + @avgRuntimeString;
   PRINT N'END;';
   PRINT N'';
   PRINT N'EXEC @retCode = msdb.dbo.sp_update_job @job_id = ' + quotename(@backupJobID) + N', @enabled = 0';
   PRINT N'    IF(@retCode = 1) ';
   PRINT N'       BEGIN';
   PRINT N'          PRINT N''Error disabling job with ID = ' + quotename(@backupJobID) + N''';';
   PRINT N'          ROLLBACK TRANSACTION;';
   PRINT N'       END;';
   PRINT N'    ELSE';
   PRINT N'       PRINT N''Backup jobs disabled successfully'';';
   PRINT N'       COMMIT TRANSACTION;';
   PRINT N'';

END

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


   PRINT N'PRINT N''Starting Failover for ' + quotename(@databasename) + N' on ' + quotename(@@SERVERNAME) + N' at ' +  convert(nvarchar, current_timestamp, 120) + N' as ' + quotename(suser_sname()) +  N'...'';';
   PRINT N'';
   PRINT N'PRINT N''Backing up the tail of the transaction log to ' + quotename(@backupFileName) + N''';';
   PRINT N'';
   PRINT N'BACKUP LOG ' + quotename(@databasename) + N' TO DISK = N''' + quotename(@backupFileName) + N'''';
   PRINT N'WITH NO_TRUNCATE , NOFORMAT , NOINIT, NAME = N''' + quotename(@databasename) + N'-Tail Transaction Log Backup''' + N', SKIP, NOREWIND, NOUNLOAD';
   PRINT N'STANDBY = ' + quotename(@standbyFileName) + N', STATS = 10';
   PRINT N'';
   PRINT N'    IF(@@ERROR <> 0)';
   PRINT N'       BEGIN'
   PRINT N'          PRINT N''Tail Transaction Log Backup Failed... Rolling back'';'
   PRINT N'          ROLLBACK TRANSACTION;';
   PRINT N'       END;';
   PRINT N'    ELSE';
   PRINT N'       PRINT N''Tail Transaction Log Backup Successful. ' + quotename(@databasename) + N' is now in a restoring state.'';';
   PRINT N'';
   PRINT N'COMMIT TRANSACTION;';
   PRINT N'';
   PRINT N'GO';
   PRINT N'';
   
   PRINT N'';
   
--End of script, continue to secondary instance script

end;