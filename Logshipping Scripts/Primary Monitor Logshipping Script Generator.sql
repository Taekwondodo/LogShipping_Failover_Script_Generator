/*

This script is run on the primary server of the logshipping setup.

Use this script to produce a T-SQL script to setup the monitor server in a logshipping configuration for the primary instances

*/

set nocount on;
go

use msdb;
go

declare @debug bit;
set @debug = 1;

--============================

declare @databases table (
   primary_id                    uniqueidentifier primary key not null
  ,database_name                 nvarchar(128) not null
  ,monitor_server_security_mode  bit not null
  ,backup_threshold              int not null
  ,threshold_alert               int not null
  ,threshold_alert_enabled       bit not null
  ,history_retention_period      int not null
);

insert into @databases(
   primary_id
  ,database_name
  ,monitor_server_security_mode
  ,backup_threshold
  ,threshold_alert
  ,threshold_alert_enabled
  ,history_retention_period
)

select
   lsmp.primary_id 
  ,lsmp.primary_database as database_name
  ,lspd.monitor_server_security_mode
  ,lsmp.backup_threshold
  ,lsmp.threshold_alert
  ,lsmp.threshold_alert_enabled
  ,lsmp.history_retention_period
from 
   log_shipping_monitor_primary as lsmp inner join log_shipping_primary_databases as lspd on (lsmp.primary_id = lspd.primary_id)
order by
   lsmp.primary_database asc;

if (@debug = 1)
   select * from @databases


declare @databaseName  nvarchar(128)
       ,@monitorServer nvarchar(128)
set @databaseName = N'';
set @monitorServer = select top 1 lspd.monitor_server from log_shipping_primary_database as lspd;

print N'--*****RUN ON ' + quotename(@monitorServer) + N'*****--';
print N'-- This script configures ' + quotename(@monitorServer) + N' for the following databases of the primary logshipping configuation on ' + quotename(@@SERVERNAME) + N':';
print N'';

while (exists(select top 1 * from @databases as d where d.database_name > @databaseName order by d.database_name asc))begin

   select top 1
      @databaseName = d.database_name
   from
      @databases as d
   where
      d.database_name > @databaseName
   order by
      d.database_name asc;

   print N'-- ' + @databaseName;

end

PRINT N'';
PRINT N'Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'*/';
PRINT N'';
PRINT N'--================================';
PRINT N'';
PRINT N'USE msdb';
PRINT N'';
PRINT N'SET nocount, arithabort, xact_abort on';
PRINT N'';
PRINT N'PRINT N''Beginning Monitor Logshipping Configurations...'';';
PRINT N'PRINT N'''';';
PRINT N'';
PRINT N'-- #elapsedTime is used to keep track of the total execution time of the script';
PRINT N'';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#elapsedTime'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #elapsedTime';
PRINT N'';
PRINT N'CREATE TABLE #elapsedTime (timestamps datetime);';
PRINT N'INSERT INTO #elapsedTime SELECT CURRENT_TIMESTAMP;';

raiserror('',0,1) WITH NOWAIT; --flush print buffer

SET @databaseName = N'';

  declare @primaryID              uniqueidentifier 
  ,@databaseName                  nvarchar(128)
  ,@monitorServerSecurityMode     bit 
  ,@backupThreshold               int 
  ,@thresholdAlert                int 
  ,@thresholdAlertEnabled         bit 
  ,@historyRetentionPeriod        int;

while (exists(select top 1 * from @databases as d where d.database_name > @databaseName order by database_name asc))begin

   select top 1
      @primaryID = d.primary_id
     ,@databaseName = d.database_name
     ,@monitorServerSecurityMode = d.monitor_server_security_mode
     ,@backupThreshold = d.backup_threshold
     ,@thresholdAlert = d.threshold_alert
     ,@thresholdAlertEnabled = d.threshold_alert_enabled
     ,@historyRetentionPeriod = d.history_retention_period
   from 
      @databases as d
   where 
      d.database_name > @databaseName
   order by
      d.database_name asc;

   print N'   EXEC msdb.dbo.sp_processlogshippingmonitorprimary ';
   print N'		 @mode = 1 ';
   print N'		,@primary_id = N''' + @primaryID + N'''';
   print N'		,@primary_server = N''' + @@SERVERNAME + N'''';
   print N'		,@monitor_server = N''' + @monitorServer + N'''';
   print N'		,@monitor_server_security_mode = ' + @monitorServerSecurityMode;
   print N'		,@primary_database = N''' + @databaseName + N'''';
   print N'		,@backup_threshold = ' + @backupThreshold;
   print N'		,@threshold_alert = ' + @thresholdAlert;
   print N'		,@threshold_alert_enabled = ' + @thresholdAlertEnabled;
   print N'		,@history_retention_period = ' + @historyRetentionPeriod;


    

end