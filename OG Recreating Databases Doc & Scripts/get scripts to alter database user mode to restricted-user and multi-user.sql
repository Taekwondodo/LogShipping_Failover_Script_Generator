/*

Use this script to produce a T-SQL script that will update all of the user databases matching filters on the current 
instance to a specified access mode.

*/

use [master]
go

declare @mode           nvarchar(60)
      , @debug          bit
      , @databaseFilter nvarchar(128);

--set @databaseFilter = N'Administration';

set @mode = N'multi_user'; -- N'restricted_user'; -- 
set @debug = 1;

--=============================

declare @databases table (
   database_name nvarchar(128)
);

insert into @databases (
   database_name
)
select
   db.name as database_name
from
   master.sys.databases as db
where
   db.state_desc = N'ONLINE'
   and db.name not in (N'master', N'model', N'msdb', N'tempdb')
   and ((@databaseFilter is null) 
      or (db.name like N'%' + @databaseFilter + N'%'))
order by
   db.name;

--=============================

if (@debug = 1) begin
   
   set nocount off;

   select
      @databaseFilter as DatabaseFilter
    , @mode           as UserAccessMode;

   select
      *
   from
      @databases as d
   order by
      d.database_name;

end else begin

   set nocount on;

end;

print N'--================================';
print N'--';
print N'-- Use the following script to alter the user access mode of the following databases on ' + quotename(@@servername) + N' to ' + upper(@mode) + N':';
print N'--';

declare @databaseName nvarchar(128);

set @databaseName = N'';

while exists(select * from @databases as d where d.database_name > @databaseName) begin

   select top 1
      @databaseName = d.database_name
   from
      @databases as d
   where
      (d.database_name > @databaseName)
   order by
      d.database_name;

   print N'--    ' + @databaseName;

end;

print N'--';
print N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
print N'--';
print N'--================================';

print N'';
print N'use [master];';
print N'go';
print N'';


set @databaseName = N'';

while exists(select * from @databases as d where d.database_name > @databaseName) begin

   select top 1
      @databaseName = d.database_name
   from
      @databases as d
   where
      d.database_name > @databaseName
   order by
      d.database_name;

   print N'print N''Updating ' + quotename(@databaseName) + N' to ' + @mode + N' access mode...'';';
   print N'go';
   print N'';

   print N'alter database ' + quotename(@databaseName) + N' set ' + @mode + N' with rollback immediate;';
   print N'go';
   print N'';

   print N'alter database ' + quotename(@databaseName) + N' set ' + @mode + N';';
   print N'go';
   print N'';

   print N'if (exists(select * from sys.databases as d where d.name = N''' + @databaseName + N''' and d.user_access_desc = N''' + @mode + N'''))';
   print N'   print N''...database ' + quotename(@databaseName) + N' is in ' + @mode + N' access mode.'';';
   print N'else';
   print N'   print N''...database ' + quotename(@databaseName) + N' is NOT in ' + @mode + N' access mode!'';';
   print N'print N'''';';
   print N'go';
   print N'';

end;

print N'print N''User access mode changes complete.'';';
print N'print N'''';';

go