/*

This script is ran on the server you want to setup as a primary for logshipping

Use this script to produce a T-SQL script to setup the server it is run on as a logshipping primary instance

*/

set nocount on;
go

use msdb;
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

declare @databases table (
   database_name    nvarchar(128) not null primary key clustered
);

insert into @databases (
   database_name
  )

select 
   d.name as database_name
from 
   master.sys.databases as d
where
   (d.state_desc = N'ONLINE')
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
order by
   d.name asc;

if not exists(select * from @databases)
   raiserror('There are no databases eligible to be configured for logshipping', 17, -1);

if (@debug = 1) begin

   select
      *
   from
      @databases AS d
   order by
      d.database_name;

end;


