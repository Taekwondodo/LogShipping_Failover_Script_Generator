/*

This script is ran on the server you want to setup as a primary ofr logshipping

Use this script to produce a T-SQL script to setup the server it is run on as a logshipping primary instance

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

