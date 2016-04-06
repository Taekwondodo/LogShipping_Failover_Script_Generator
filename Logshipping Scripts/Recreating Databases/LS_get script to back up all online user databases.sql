/*

Use this script to produce a T-SQL script to back up all of the online databases, matching filters, to the default backup 
location on the current server.

*/

set nocount on;
go

use master;
go

declare @backupFilePath nvarchar(260)
      , @debug          bit
      , @exclude_system bit
      , @tailLog        bit
      , @copyOnly       bit;

declare @databaseFilter table (
   DatabaseName nvarchar(128)
);

set @debug = 1;
set @exclude_system = 1;
set @tailLog = 0;
set @copyOnly = 1;

--insert into @databaseFilter (
--  DatabaseName
--)
--select N'Footprints' --union all
--select N'AssetManager'
--select N'DBA';
--;

--================================

exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'BackupDirectory'
 , @value      = @backupFilePath output;

if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';

if object_id(N'tempdb..#backup_files') is not null 
   drop table #backup_files;

create table #backup_files (
   database_name    nvarchar(128) not null primary key clustered
 , backup_file_name nvarchar(260)
);

insert into #backup_files (
   database_name
 , backup_file_name
)
select
   d.name       as database_name
 , replace(replace(replace(replace(
      N'{backup_path}{database_name}_backup_{backupTime}.{extension}'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', d.name)
    , N'{backupTime}', replace(replace(replace(convert(nvarchar(16), current_timestamp, 120), N'-', N''), N':', N''), N' ', N''))
	 , N'{extension}', case when @tailLog = 1 then N'trn' else N'bak' end) as backup_file_name
from
   sys.databases as d inner join msdb.dbo.log_shipping_primary_databases as lspd on (d.name = lspd.primary_database)  -- Filter for LS databases
where
   (d.state_desc = N'ONLINE')
   and ((@exclude_system = 0)
      or (d.name not in (N'master', N'model', N'msdb')))
   and (d.name <> N'tempdb')
   and ((not exists(select * from @databaseFilter))
      or (exists(select * from @databaseFilter as df where d.name = df.DatabaseName)))
order by
   d.name;

select
   @backupFilePath as BackupFilePath
 , @exclude_system as ExcludeSystemDatabases
 , @tailLog			 as TailLogBackup
 , @copyOnly       as CopyOnly;

select
   *
from
   @databaseFilter as df
order by
   df.DatabaseName;

if (@debug = 1) begin

   select
      *
   from
      #backup_files as bf
   order by
      bf.database_name;

end;

select
   d.name  as database_name
 , mf.[file_id]
 , mf.name as logical_name
 , mf.type_desc
 , mf.physical_name
from
   sys.master_files as mf
   inner join sys.databases as d
      on mf.database_id = d.database_id
   inner join #backup_files as bf
      on d.name = bf.database_name
order by
   d.name
 , mf.[file_id];



--================================

declare @numDatabases int;

set @numDatabases = coalesce((select count(distinct bf.database_name) from #backup_files as bf), 0);

print N'--================================';
print N'--';
print N'-- Use the following script to take '
    + case
         when @numDatabases = 1
            then N'a '
         else N''
      end
    + case 
         when @copyOnly = 1
            then N'copy-only '
         else N'' 
      end
    + case 
         when @tailLog = 1 
            then N'tail log ' 
         else N'' 
      end 
    + N'backup'
    + case
         when @numDatabases = 1
            then N''
         else N's'
      end 
    + N' of the following database' 
    + case
         when @numDatabases = 1
            then N''
         else N's'
      end 
    + N' on ' + quotename(@@servername) + ':';
print N'--';

declare @databaseName   nvarchar(128)
      , @backupFileName nvarchar(260)
      , @maxLen         int;

set @maxLen = (select max(datalength(bf.database_name)) from #backup_files as bf);

set @databaseName = N'';

while exists(select * from #backup_files as bf where bf.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = bf.backup_file_name
   from
      #backup_files as bf
   where
      (bf.database_name > @databaseName)
   order by
      bf.database_name;

   print N'--    ' + left(@databaseName + replicate(N' ', @maxLen / 2), @maxLen / 2) + N'   ' + @backupFileName;

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

while exists(select * from #backup_files as bf where bf.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = replace(bf.backup_file_name, N'''', N'''''')
   from
      #backup_files as bf
   where
      (bf.database_name > @databaseName)
   order by
      bf.database_name;

   print N'';
   print N'print N''Backing up ' + case when @tailLog = 1 then N'the tail log of ' else N'' end + N'database ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + N' to file "' + replace(@backupFileName, N'''', N'''''') + '" at '' + convert(nvarchar, current_timestamp, 120) + '' as '' + quotename(suser_sname()) + N''...'';';
   print N'print N''''';
   print N'go';
   print N'';

   print N'backup ' + case when @tailLog = 1 then N'log' else N'database' end + N' ' + quotename(@databaseName) + N' to disk = N''' + replace(@backupFileName, N'''', N'''''') + '''';
   print N'   with';
   print N'      noformat';      -- Whether to create a new or override an existing media set (noformat creates a new media set)
   print N'    , init';          -- Specifies that all backup sets within the device should be overwritten, but preserves the media header
   print N'    , name = N''' + @databaseName + N'-' + case when @tailLog = 1 then N'Tail Log' else N'Full' end + N' Database Backup''';
   print N'    , skip';          -- Skip/noskip controls whether a backup operation checks the expiration date and time of the backup sets on the media before overwriting (skip = don't check)
   print N'    , norewind';      -- For TAPE devices. Whether to unwind then release the tape or keep it open after the backup. Keeping it open improves performance when performing multiple backups to the tape
   print N'    , nounload';      -- Implied by norewind. UNLOAD/NOUNLOAD whether to unload or keep loaded the tape on the tape drive after the backup
   print N'    , stats = 10';
   if (@copyOnly = 1) begin
      print N'    , copy_only';  -- Makes a backup that doesn't interfere with the normal sequence of server backups. Useful when making backups for special purposes
   end;
   if (@tailLog = 1) begin
      print N'    , no_truncate';
      print N'    , norecovery';
   end;
   print N'    , checksum;';     -- Error management. Specifies that the backup operation will verify each page for checksum and torn page. Generates a checksum for the entire backup
   print N'go';

   print N'';
   print N'print N''Verifying ' + case when @tailLog = 1 then N'tail log ' else N'' end + N'backup of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + N' to file "' + replace(@backupFileName, N'''', N'''''') + '" at '' + convert(nvarchar, current_timestamp, 120) + '' as '' + quotename(suser_sname()) + N''...'';';
   print N'print N''''';
   print N'go';
   print N'';

   print N'declare @backupSetId as int;';
   print N'';
   print N'select top 1';
   print N'   @backupSetId = position';
   print N'from';
   print N'   msdb..backupset as b';
   print N'where';
   print N'   b.database_name = N''' + @databaseName + N'''';
   print N'order by';
   print N'   b.backup_set_id desc;';
   print N'';
   print N'if @backupSetId is null begin';
   print N'   raiserror(N''Verify failed. Backup information for database ''''' + @databaseName + ''''' not found.'', 16, 1);';
   print N'end;';
   print N'';
   print N'restore verifyonly from disk = N''' + replace(@backupFileName, N'''', N'''''') + N''' with file = @backupSetId, nounload, norewind;';
   print N'go';
   print N'';
      
   print N'print N'''';';
   print N'print N''' + case when @tailLog = 1 then N'Tail log backup' else N'Backup' end + N' of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + ' completed at '' + convert(nvarchar, current_timestamp, 120) + ''.'';';
   print N'print N'''';';
   print N'go';

end;

go


