/*

Use this script to produce a T-SQL script to back up all of the online databases, matching filters, to the default backup 
location on the current server.

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
set @exclude_system = 0;

--set @databaseFilter = N'Footprints';

--================================

exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'BackupDirectory'
 , @value      = @backupFilePath output;

if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';

declare @backup_files table (
   database_name    nvarchar(128) not null primary key clustered
 , backup_file_name nvarchar(260)
);

insert into @backup_files (
   database_name
 , backup_file_name
)
select
   d.name       as database_name
--replace works as such: replace(stringToSearchThrough, substringToReplace, valueToReplaceWith)
--The following is just setting up the name of the backup files for each db
 , replace(replace(replace(
      N'{backup_path}{database_name}_backup_{backupTime}.bak'
    , N'{backup_path}', @backupFilePath)
    , N'{database_name}', d.name)
    , N'{backupTime}', replace(replace(replace(convert(nvarchar(16), current_timestamp, 120), N'-', N''), N':', N''), N' ', N'')) as backup_file_name
from
   sys.databases as d

--We don't want to make backups if a db is offline, a system db, or if it matches our filter
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
print N'-- Use the following script to back up the following database backups on ' + quotename(@@servername) + ':';
print N'--';

declare @databaseName   nvarchar(128)
      , @backupFileName nvarchar(260)
      , @maxLen         int;

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

   print N'';
   print N'print N''Backing up database ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + N' to file "' + replace(@backupFileName, N'''', N'''''') + '" at '' + convert(nvarchar, current_timestamp, 120) + '' as '' + quotename(suser_sname()) + N''...'';';
   print N'print N''''';
   print N'go';
   print N'';

   print N'backup database ' + quotename(@databaseName) + N' to disk = N''' + replace(@backupFileName, N'''', N'''''') + '''';
   print N'   with';
   print N'      noformat';
   print N'    , init';
   print N'    , name = N''' + @databaseName + N'-Full Database Backup''';
   print N'    , skip';
   print N'    , norewind';
   print N'    , nounload';
   print N'    , stats = 10';
   print N'    , checksum;';
   print N'go';

   print N'';
   print N'print N''Verifying backup of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + N' to file "' + replace(@backupFileName, N'''', N'''''') + '" at '' + convert(nvarchar, current_timestamp, 120) + '' as '' + quotename(suser_sname()) + N''...'';';
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
   print N'print N''Backup of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + ' completed at '' + convert(nvarchar, current_timestamp, 120) + ''.'';';
   print N'print N'''';';
   print N'go';

end;

go
