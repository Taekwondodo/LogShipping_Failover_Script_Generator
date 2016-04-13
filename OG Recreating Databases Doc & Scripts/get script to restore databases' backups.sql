/*

Use this script to produce a T-SQL script to restore the given database backups over the specified databases.

Run this script on the destination server so that it can detect the proper data and t-log file paths to which the 
mdf/ndf/ldf/ft files should be restored.

The target databases must already exist and need to have the same basic logical file layout as the original databases 
that produced the backups.

Use the companion file 'convert backup paths into sql to list database name and backup path.xlsx' to convert:
   
   a list of backup file names into the input for @backup_files
   and a list of database file names into input for @database_files

*/

set nocount on;
go

use master;
go


declare @backup_files table (
   database_name      nvarchar(128) not null primary key clustered
 , backup_file_name   nvarchar(260)
 , [keep_replication] bit
 , backup_type        nvarchar(128)
);

declare @database_files table (
   database_name nvarchar(128) not null
 , [file_id]     int           not null
 , logical_name  nvarchar(128) not null
 , type_desc     nvarchar(60)  null
 , physical_name nvarchar(260) not null
);

declare @dataFilePath nvarchar(260)
      , @logFilePath  nvarchar(260)
      , @ownerLogin   nvarchar(128)
      , @debug        bit
      , @withRecovery bit
      , @quiesce      bit;

set @debug = 1;
set @ownerLogin = N'sa';
set @withRecovery = 0; -- For LS purposes we want the databases to be either recovering or standby/read-only
set @quiesce = 1;

insert into @backup_files (
   database_name
 , [keep_replication]
 , backup_type
 , backup_file_name
)
select N'Test', 0, N'FULL', N'C:\DBFiles\Backup\Full\Test_backup_201604131700.bak';


insert into @database_files (
   database_name
 , [file_id]
 , logical_name
 , type_desc
 , physical_name
)
select N'Test', 1, N'Test', N'ROWS', N'Test.mdf' union all
select N'Test', 2, N'Test_log', N'LOG', N'Test_log.ldf';




--================================

set @ownerLogin = coalesce(@ownerLogin, N'sa');

if (@debug = 1) begin

   select
      *
   from
      @backup_files as bf
   order by
      bf.database_name;

end;

exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'DefaultData'
 , @value      = @dataFilePath output;

exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'DefaultLog'
 , @value      = @logFilePath output;

if (@dataFilePath not like N'%\') set @dataFilePath = @dataFilePath + N'\';

if (@logFilePath not like N'%\') set @logFilePath = @logFilePath + N'\';

select
   @dataFilePath as DataFilePath
 , @logFilePath  as LogFilePath
 , @ownerLogin   as OwnerLogin
 , @withRecovery as WithRecovery
 , @quiesce      as Quiesce;

if object_id(N'tempdb..#databaseFiles') is not null drop table #databaseFiles;

create table #databaseFiles (
   database_name  nvarchar(128) not null
 , [file_id]      int           not null
 , [logical_name] nvarchar(128)
 , type_desc      nvarchar(60)
 , physical_name  nvarchar(260) 
 , move_cmd       nvarchar(max)
   constraint [PK_tmp_databaseFiles] primary key clustered (database_name, [file_id])
);

insert into #databaseFiles (
   database_name 
 , [file_id]
 , logical_name
 , type_desc
 , physical_name
 , move_cmd
)
--select
--   d.name  as database_name
-- , mf.[file_id]
-- , mf.name as logical_name
-- , mf.type_desc
-- , mf.physical_name
-- , N'move N''' + mf.name 
-- + N''' to N''' 
-- + replace(
--      case
--         when mf.type_desc = N'LOG'
--            then @logFilePath 
--         when mf.type_desc = N'FULLTEXT'
--            then @dataFilePath 
--               + case 
--                  when n.[FileName] like d.name + N'%' 
--                     then N'' 
--                  else d.name + N'_' 
--                 end
--         else @dataFilePath 
--      end 
--    , N'''', N'''''')
-- + n.[FileName] + N''''
--from
--   sys.master_files as mf
--   inner join sys.databases as d
--      on mf.database_id = d.database_id
--   outer apply (
--      select 
--         substring(mf.physical_name, len(mf.physical_name) - charindex('\', reverse(mf.physical_name)) + 2, len(mf.physical_name)) as [FileName]
--       , substring(mf.physical_name, 1, len(mf.physical_name) - charindex('\', reverse(mf.physical_name)) + 1) as FilePath
--   ) as n
--where
--   (d.name in (
--      select
--         bf.database_name
--      from
--         @backup_files as bf
--   ))
--order by
--   d.name
-- , mf.[file_id];

select
    df.database_name
  , df.[file_id]
  , df.logical_name
  , df.type_desc
  , df.physical_name  
 , N'move N''' + df.logical_name
 + N''' to N''' 
 + replace(
      case
         when df.type_desc = N'LOG'
            then @logFilePath 
         when df.type_desc = N'FULLTEXT'
            then @dataFilePath 
               + case 
                  when df.physical_name like df.database_name + N'%' 
                     then N'' 
                  else df.database_name + N'_' 
                 end
         else @dataFilePath 
      end 
    , N'''', N'''''')
 + df.physical_name + N''''
from
   @database_files as df
order by
   df.database_name
 , df.[file_id];

if (@debug = 1) begin

   select
      *
   from
      #databasefiles as df
   order by
      df.database_name
    , df.[file_id];

end;

--================================

print N'--================================';
print N'--';
print N'-- Use the following script to restore the following database backups on ' + quotename(@@servername) + ':';
print N'--';

declare @databaseName    nvarchar(128)
      , @backupFileName  nvarchar(260)
      , @maxLen          int
      , @keepReplication bit
      , @type   nvarchar(128);

set @maxLen = (select max(datalength(bf.database_name)) from @backup_files as bf);

set @databaseName = N'';

while exists(select * from #databaseFiles as f where f.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = bf.backup_file_name
    , @keepReplication = bf.[keep_replication]
    , @type = bf.backup_type
   from
      @backup_files as bf
   where
      (bf.database_name > @databaseName)
      and (exists(select * from #databaseFiles as f where bf.database_name = f.database_name))
   order by
      bf.database_name;

   print N'--    ' + left(@databaseName + replicate(N' ', @maxLen / 2), @maxLen / 2) 
       + N'   ' + @backupFileName
       + N' ' 
       + @type 
       + case when @keepReplication = 1 then N' KEEP_REPLICATION' else N'' end;

end;

print N'--';

print N'-- Data and t-log files will be moved to "' + @dataFilePath + N'" and "' + @logFilePath + N'", respectively.';
print N'--';

print N'-- The database owner will be set to ' + quotename(@ownerLogin) + N', if it can be found.';
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

while exists(select * from #databaseFiles as f where f.database_name > @databaseName) begin

   select top 1
      @databaseName = bf.database_name
    , @backupFileName = replace(bf.backup_file_name, N'''', N'''''')
    , @keepReplication = bf.[keep_replication]
    , @type = bf.backup_type
   from
      @backup_files as bf
   where
      (bf.database_name > @databaseName)
      and (exists(select * from #databaseFiles as f where bf.database_name = f.database_name))
   order by
      bf.database_name;

   print N'';
   print N'print N''Beginning ' + @type + ' restoration of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + ' at '' + convert(nvarchar, current_timestamp, 120) + '' as '' + quotename(suser_sname()) + N''...'';';
   print N'print N''''';
   print N'go';
   print N'';

   if (@quiesce = 1) begin

      print N'print N''quiescing ' + quotename(@databaseName) + N'...'';';
      print N'go';
      print N'alter database ' + quotename(@databaseName) + N' set single_user with rollback immediate;';
      print N'go';
      print N'';

   end;

   print N'print N''''';
   print N'print N''restoring file "' + @backupFileName + N'"...'';';
   print N'go';

   print N'restore ' + case when @type in (N'FULL', 'DIFF') then N'database' else 'log' end + N' ' + quotename(@databaseName) + N' from disk = N''' + replace(@backupFileName, N'''', N'''''') + '''';
   print N'   with';
   print N'      file = 1';

   set @fileID = 0;

   while exists(select * from #databaseFiles as df where df.database_name = @databaseName and df.[file_id] > @fileID) begin

      select top 1
         @fileID = df.[file_id]
       , @cmd = df.move_cmd
      from
         #databaseFiles as df
      where
         df.database_name = @databaseName
         and df.[file_id] > @fileID
      order by
         df.database_name
       , df.[file_id];

      print N'    , ' + @cmd;

   end;

   print N'    , replace';
   print N'    , ' + case when @withRecovery = 1 then N'' else N'no' end + N'recovery';
   print N'    , nounload';

   if (@keepReplication = 1) and (@withRecovery = 1) begin

      print N'    , keep_replication';

   end;

   print N'    , stats = 10;';
   print N'go';
   print N'';

   if (@withRecovery = 1) begin

      print N'print N''''';
      print N'print N''setting the database owner for ' + quotename(@databaseName) + N'...'';';  
      print N'go';
      print N'if (exists(select * from [master].sys.server_principals where name = N''' + @ownerLogin + N''')) begin';
      print N'   alter authorization on database::' + quotename(@databaseName) + N' to ' + quotename(@ownerLogin) + N';';
      print N'end else begin';
      print N'   raiserror (N''Unable to find login ' + quotename(@ownerLogin) + N' to set owner of database ' + quotename(@databaseName) + N'!'', 16, 1);';
      print N'end;';
      print N'go';

      print N'print N''''';
      print N'print N''returning ' + quotename(@databaseName) + N' to multi-user mode...'';';
      print N'go';
      print N'alter database ' + quotename(@databaseName) + N' set multi_user;';
      print N'go';
      print N'';

   end;
      
   print N'print N'''';';
   print N'print N''Restoration of ' + quotename(@databaseName) + N' on ' + quotename(@@servername) + ' completed at '' + convert(nvarchar, current_timestamp, 120) + ''.'';';
   print N'print N'''';';
   print N'go';
   print N'';

end;

go

if object_id(N'tempdb..#databaseFiles') is not null drop table #databaseFiles;
