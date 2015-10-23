/*

This script is ran on the original primary instance after it has been configured as the failover secondary

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
--Get necessary information about the databases forthe proc

declare @databases table(
    secondary_id               uniqueidentifier not null primary key 
   ,database_name              nvarchar(128) not null
   ,primary_server             nvarchar(128) not null
   ,primary_database           nvarchar(128) not null
   ,monitor_server             nvarchar(128) not null
   ,restore_threshold          int not null
   ,threshold_alert            int not null
   ,history_retention_period   int not null
   ,threshold_alert_enabled    tinyint not null
)

insert into @databases(
    secondary_id
   ,database_name
   ,primary_server
   ,primary_database
   ,monitor_server
   ,restore_threshold
   ,threshold_alert
   ,history_retention_period
   ,threshold_alert_enabled
)
select
   lsms.secondary_id as secondary_id
  ,lsms.secondary_database as database_name
  ,lsms.primary_server as primary_server
  ,lsms.primary_database as primary_database
  ,lss.monitor_server as monitor_server
  ,lsms.restore_threshold as restore_threshold
  ,lsms.threshold_alert as threshold_alert
  ,lsms.history_retention_period as history_retention_period
  ,lsms.threshold_alert_enabled as threshold_alert_enabled
  
from
   log_shipping_monitor_secondary as lsms 
   LEFT JOIN log_shipping_secondary as lss on (lsms.secondary_id = lss.secondary_id)
where 
      --Doesn't matter if a db is offline or not as long as it exists in lsms since we're just updating the monitor with the new logshipping configuration

      ((@databaseFilter is null) 
        or (lsms.secondary_database like N'%' + @databaseFilter + N'%'))

order by 
   lsms.secondary_database ASC;

IF(@debug = 1)BEGIN

   SELECT 
      *
   FROM 
      @databases AS d
    ORDER BY 
      d.database_name;
end

--===========================

DECLARE @secondaryID              nvarchar(128)
       ,@databaseName             nvarchar(128)
       ,@primaryServer            nvarchar(128)
       ,@primaryDatabase          nvarchar(128)
       ,@monitorServer            nvarchar(128)
       ,@restoreThreshold         nvarchar(10)
       ,@thresholdAlert           nvarchar(10)
       ,@historyRetentionPeriod   nvarchar(10)
       ,@thresholdAlertEnabled    nvarchar(1) 

SET @monitorServer = (SELECT TOP 1 d.monitor_server FROM @databases AS d)
SET @databaseName = N'';

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Run on ' + quotename(@monitorServer);
PRINT N'-- Use the following script to update monitor server ' + quotename(@monitorServer) + N' with the new failover secondary logshipping configurations of the following databases on ' + quotename(@@SERVERNAME) + N':';
PRINT N'--';

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE @databaseName < d.database_name))BEGIN

   SELECT TOP 1
      @databaseName = d.database_name
   FROM 
      @databases AS d
   WHERE 
      @databaseName < d.database_name
   ORDER BY
      d.database_name;

   PRINT N'-- ' + quotename(@databaseName);

END;

--Start the actual script

SET @databaseName = N'';

PRINT N'';
PRINT N'BEGIN TRANSACTION';
PRINT N'';

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE @databaseName < d.database_name))BEGIN

   SELECT TOP 1
      @secondaryID = d.secondary_id
     ,@databaseName = d.database_name
     ,@primaryServer = d.primary_server
     ,@primaryDatabase = d.primary_database
     ,@restoreThreshold = d.restore_threshold
     ,@thresholdAlert = d.threshold_alert
     ,@historyRetentionPeriod = d.history_retention_period
     ,@thresholdAlertEnabled = d.threshold_alert_enabled
   FROM 
      @databases AS d
   WHERE 
      @databaseName < d.database_name
   ORDER BY
      d.database_name;

   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'PRINT N''Inserting ' + quotename(@databaseName) + N'''''s logshipping configuartion'';';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_processlogshippingmonitorsecondary'; 
   PRINT N'		 @mode = 1 --1 = create, 2 = delete, 3 = update';
   PRINT N'	 	,@secondary_server = N''' + @@SERVERNAME + N''''; 
   PRINT N'	 	,@secondary_database = N''' + @databaseName + N'''';
   PRINT N'	 	,@secondary_id = N''' + @secondaryID + N'''';
   PRINT N'	 	,@primary_server = N''' + @primaryServer + N'''';
   PRINT N'	 	,@primary_database = N''' + @primaryDatabase + N''''; 
   PRINT N'	 	,@restore_threshold = ' + @restoreThreshold;
   PRINT N'	 	,@threshold_alert = ' + @thresholdAlert;
   PRINT N'	 	,@threshold_alert_enabled = ' + @thresholdAlertEnabled;
   PRINT N'	 	,@history_retention_period	= ' + @historyRetentionPeriod;
   PRINT N'	 	,@monitor_server = N''' + @monitorServer + N''''; 
   PRINT N'	 	,@monitor_server_security_mode = 1';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''An error occurred while executing sp_processlogshippingmonitorsecondary for ' + quotename(@databaseName) + N'. Rolling back and quitting execution...'';';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';
   PRINT N'PRINT N''' + quotename(@databaseName) + N' successfully inserted'';';
   PRINT N'PRINT N'''';';
END;
PRINT N'PRINT N''All databases successfully inserted'';';
PRINT N'COMMIT TRANSACTION;';
