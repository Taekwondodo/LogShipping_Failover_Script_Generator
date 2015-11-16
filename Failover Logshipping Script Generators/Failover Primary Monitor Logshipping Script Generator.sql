/*

This script is ran on the original secondary instance after it has been configured as the failover primary

Use this script to produce a T-SQL script to run on the server's monitor for logshipping configuration

*/

set nocount, arithabort, xact_abort on
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
--Get information about the databases

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
where 
      --Doesn't matter if a db is offline or not as long as it exists in lspd since we're just updating the monitor with the new logshipping configuration

      ((@databaseFilter is null) 
        or (lspd.primary_database like N'%' + @databaseFilter + N'%'))
order by 
   lspd.primary_database ASC;

IF(@debug = 1)BEGIN

   SELECT 
      *
   FROM 
      @databases AS d
    ORDER BY 
      d.database_name;
end

--===========================

DECLARE @primaryID                nvarchar(128)
       ,@databaseName             nvarchar(128)
       ,@monitorServer            nvarchar(128)
       ,@backupThreshold          nvarchar(10)
       ,@thresholdAlert           nvarchar(10)
       ,@historyRetentionPeriod   nvarchar(10)
       ,@thresholdAlertEnabled    nvarchar(1) --bit

SET @monitorServer = (SELECT TOP 1 d.monitor_server FROM @databases AS d)
SET @databaseName = N'';

PRINT N'--================================';
PRINT N'--*****RUN ON ' + quotename(@monitorServer) + N'*****';
PRINT N'--';
PRINT N'-- Use the following script to update monitor server ' + quotename(@monitorServer) + N' with the new primary failover logshipping configurations of the following databases on ' + quotename(@@SERVERNAME) + N':';
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

PRINT N'';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'';
PRINT N'set nocount, arithabort, xact_abort on';

--Start the actual script

SET @databaseName = N'';

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE @databaseName < d.database_name))BEGIN

   SELECT TOP 1
      @primaryID = d.primary_id
     ,@databaseName = d.database_name
     ,@backupThreshold = d.backup_threshold
     ,@thresholdAlert = d.threshold_alert
     ,@historyRetentionPeriod = d.history_retention_period
     ,@thresholdAlertEnabled = d.threshold_alert_enabled
   FROM 
      @databases AS d
   WHERE 
      @databaseName < d.database_name
   ORDER BY
      d.database_name;

   PRINT N''
   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION';
   PRINT N'BEGIN TRY';
   PRINT N'';
   PRINT N'    PRINT N''=================================='';';
   PRINT N'    PRINT N''Inserting ' + quotename(@databaseName) + N'''''s logshipping configuartion'';';
   PRINT N'    PRINT N'''';';
   PRINT N'';
   PRINT N'    EXEC msdb.dbo.sp_processlogshippingmonitorprimary'; 
   PRINT N'		    @mode = 1'; --1 = create, 2 = delete, 3 = update  
   PRINT N'	 	    ,@primary_id = N''' + @primaryID + N''''; 
   PRINT N'	 	    ,@primary_server = N''' + @@SERVERNAME + N''''; 
   PRINT N'	 	    ,@monitor_server = N''' + @monitorServer + N'''';
   PRINT N'	 	    ,@monitor_server_security_mode = 1';
   PRINT N'	 	    ,@primary_database = N''' + @databaseName + N'''';
   PRINT N'	 	    ,@backup_threshold = ' + @backupThreshold;
   PRINT N'	 	    ,@threshold_alert = ' + @thresholdAlert;
   PRINT N'	 	    ,@threshold_alert_enabled = ' + @thresholdAlertEnabled; 
   PRINT N'	 	    ,@history_retention_period = ' + @historyRetentionPeriod;
   PRINT N'';
   PRINT N'    IF(@@ERROR <> 0)BEGIN';
   PRINT N'      PRINT N'''';';
   PRINT N'      PRINT N''There was an issue updating ' + quotename(@monitorServer) + N'. Rolling back and quitting batch execution...'';';
   PRINT N'      PRINT N'''';';
   PRINT N'      ROLLBACK TRANSACTION;';
   PRINT N'      RETURN;';
   PRINT N'    END;';
   PRINT N'';
   PRINT N'    COMMIT TRANSACTION;';
   PRINT N'    PRINT N''Updated ' + quotename(@monitorServer) + N' successfully '';';
   PRINT N'    PRINT N'''';';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''There was an issue updating the monitor server. Rolling back and quitting batch exeuciton...'';';
   PRINT N'    PRINT N'''';';
   PRINT N'    ROLLBACK TRANSACTION';
   PRINT N'    RETURN;';
   PRINT N'END CATCH;';
   PRINT N'';

   raiserror(N'',0,1) WITH NOWAIT; --Flush print buffer
END;

PRINT N' PRINT N'' *****Updating ' + quotename(@monitorServer) + N' complete. Proceed to Failover Secondary Logshipping*****'';';

