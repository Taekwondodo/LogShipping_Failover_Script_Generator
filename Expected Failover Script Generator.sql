/*

Use this script to produce a T-SQL script to failover all of the online databases, matching filters, to the backup location specified during 
their logshipping configurations

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
--Instead of using the registry to find the backup we'll use msdb.dbo.log_shipping_primary_databases, which also functions as the check to make sure the db is logshipped
--

SELECT top 1
   @backupFilePath = backup_directory
FROM msdb.dbo.log_shipping_primary_databases
;

if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';

declare @backup_files table (
   database_name    nvarchar(128) not null primary key clustered
 , backup_file_name nvarchar(260)
);

insert into @backup_files (
   database_name
 , backup_file_name
)
--Changed the format of {backupTime} to include milliseconds so it will fit the formatting of the other logshipping files
--After some testing I found that it is in fact necessary to have the formatting this way. A .trn file that left out the seconds and milliseconds was not
--found by the secondary copy job. A later backup with the necessary seconds and milliseconds was found, however. This may be due to the restore job using the datetime
--as logging information
select
   d.name       as database_name
 , replace(replace(replace(
      N'{backup_path}{database_name}_{backupTime}.trn'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', d.name)
    , N'{backupTime}', replace(replace(replace(replace(convert(nvarchar(19), current_timestamp, 121), N'-', N''), N':', N''),N'.', N''), N' ', N'')) AS backup_file_name
from
   sys.databases as d
--
--We don't want to make backups if a db is offline, a system db, not logshipped, or if it matches our filter
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

--================================

print N'--================================';
print N'--';
print N'-- Use the following script to perform a logship failback for the following databases on ' + quotename(@@servername) + ':';
print N'--';

declare @databaseName   nvarchar(128)
      , @backupFileName nvarchar(260)
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
print N'use [master];';
print N'go';

set @databaseName = N'';

declare @cmd    nvarchar(max)
      , @fileID int;

while exists(select * from @backup_files as bf where bf.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = replace(bf.backup_file_name, N'''', N'''''')
   from
      @backup_files as bf
   where
      (bf.database_name > @databaseName)
   order by
      bf.database_name;

   SELECT 
      @backupJobID = backup_job_id
   FROM
      msdb.dbo.log_shipping_primary_databases AS lspd
   WHERE
      primary_database = @databaseName;
   

   PRINT N'PRINT N''Beginning Transaction'';';
   PRINT N'';
   PRINT N'DECLARE @retCode int';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION LS1';
   PRINT N''
   PRINT N'GO';
   PRINT N'';

   PRINT N'PRINT N''Starting Failover for ' + quotename(@databasename) + N' on ' + quotename(@@SERVERNAME) + N' at ' +  convert(nvarchar, current_timestamp, 120) + N' as ' + quotename(suser_sname()) +  N'...'';';

   PRINT N'print N''Stopping Logshipping jobs on ' + quotename(@@SERVERNAME) + N''';';
   PRINT N'@retCode = exec sp_stop_job @job_id = ' + quotename(@backupJobID);
   PRINT N'    IF(@retCode == 1) ';
   PRINT N'       BEGIN';
   PRINT N'          PRINT N''Error stopping backup job'';';
   PRINT N'          ROLLBACK TRANSACTION LS1;';
   PRINT N'       END';
   PRINT N'    ELSE';
   PRINT N'       PRINT N''Backup job stopped successfully'';';
   PRINT N'';

   PRINT N'PRINT N''Backing up the tail of the transaction log to ' + quotename(@databasename) + N''';';
   PRINT N'BACKUP LOG ' + quotename(@databasename) + N' TO DISK = N''' + quotename(@backupFileName) + N'''';
   PRINT N'WITH NO_TRUNCATE , NOFORMAT , NOINIT, NAME = N''' + quotename(@databasename) + N'-Tail Transaction Log Backup''' + N', SKIP, NOREWIND, NOUNLOAD, NORECOVERY, STATS = 10'
   PRINT N'    IF(@@ERROR <> 0)';
   PRINT N'       BEGIN'
   PRINT N'          PRINT N''Tail Transaction Log Backup Failed... Rolling back'';'
   PRINT N'          ROLLBACK TRANSACTION LS1;';
   PRINT N'       END'
   PRINT N'GO'
   PRINT N'PRINT N''Tail Transaction Log Backup Successful. ' + @databasename + N' is now in a restoring state.'';';
   
--End of script, continue to secondary instance script

end