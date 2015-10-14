/*

This script is ran on the original secondary instance after it has been configured as the failover primary

Use this script to produce a T-SQL script to run on the server's monitor for logshipping configuration

*/

set nocount on;
go

use msdb;
go

declare @databaseFilter nvarchar(128)
      , @debug          bit
      , @exclude_system bit;
        

set @debug = 1;
set @exclude_system = 1; --So system tables are excluded

--set @databaseFilter = N'Footprints';

--================================
--

declare @databases table(
    primary_id                 uniqueidentifier not null primary key 
   ,database_name              nvarchar(128) not null
   ,monitor_server             nvarchar(128) not null
   ,backup_threshold           int not null
   ,threshold_alert            int not null
   ,history_retention_period   int not null
   ,threshold_alert_enabled    tinyint not null
)

insert into @databases(
    primary_id
   ,database_name
   ,monitor_server
   ,backup_threshold
   ,threshold_alert
   ,history_retention_period
   ,threshold_alert_enabled
)
select
   lspd.primary_id as primary_id
  ,lspd.primary_database as database_name
  ,lspd.monitor_server as monitor_server
  ,lsmp.backup_threshold as backup_threshold
  ,lsmp.threshold_alert as threshold_alert
  ,lsmp.history_retention_period as history_retention_period
  ,lsmp.threshold_alert_enabled as threshold_alert_enabled
from
   log_shipping_monitor_primary as lsmp 
   LEFT JOIN log_shipping_primary_databases as lspd on (lsmp.primary_id = lspd.primary_id)
   LEFT JOIN master.sys.databases as d on (d.name = lspd.primary_database)
where 
      --we don't want a database that is offline or has yet to be restored

      (d.state_desc = N'ONLINE')
      and d.is_read_only = 0
      and d.is_in_standby = 0
      and ((@databaseFilter is null) 
         or (d.name like N'%' + @databaseFilter + N'%'))
order by 
   lspd.primary_database ASC;


