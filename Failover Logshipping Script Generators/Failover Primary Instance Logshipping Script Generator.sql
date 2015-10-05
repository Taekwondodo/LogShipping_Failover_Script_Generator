/*

Use this script to produce a T-SQL script to run on the secondary instance you're failing over to to configure it as a primary instance for the server you're failover over from

*/

set nocount on;
go

use master;
go

declare @databaseFilter nvarchar(128)
      , @debug          bit
      , @exclude_system bit;
        

set @debug = 1;
set @exclude_system = 1; --So system tables are excluded

--set @databaseFilter = N'Footprints';

--================================
--
declare @databases table (
   secondary_id     uniqueidentifier not null primary key
  ,database_name    nvarchar(128) not nul
);

insert into @databases (
   database_name
  ,secondary_id
)
select
   lssd.secondary_database as database_name, lssd.secondary_id as secondary_id
from
   msdb.dbo.log_shipping_secondary_databases AS lssd 
   LEFT JOIN sys.databases AS d ON (lssd.secondary_database = d.name)
--
--We don't want a db if it is offline, not yet restored, or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   AND d.is_read_only = 0 
   AND d.is_in_standby = 0
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lssd.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   raiserror('There are no databases eligible to be configured for logshipping', 20, -1);

select
   @databaseFilter as DatabaseFilter
 , @exclude_system as ExcludeSystemDatabases;

if (@debug = 1) begin

   select
      *
   from
      @databases AS d
   order by
      d.database_name;

end;

--================================

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Use the following script to configure failover logshipping for the following databases as primaries on ' + quotename(@@servername) + ':';
PRINT N'--';

DECLARE @databaseName nvarchar(128)

SET @databaseName = N'';

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
   FROM
      @databases AS d 
   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT N'-- ' + @databaseName;

END;     

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
PRINT N'';
PRINT N'PRINT N''Beginning Logshipping Configurations...'';';
PRINT N'PRINT N'''';';
PRINT N'';
PRINT N'BEGIN TRANSACTION;'
PRINT N'';

--
--End of setup, start logshipping 
--
DECLARE @backupPath           nvarchar(260)
       ,@monitorServer        nvarchar(128)
       ,@secondaryServer      nvarchar(128)
       ,@secondaryDatabase    nvarchar(128)
       ,@currentDate          nvarchar(8) --Needs to be YYYYMMHH format 

SET @databaseName = N'';
SET @currentDate = convert(nvarchar(8), CURRENT_TIMESTAMP, 112); --YYYYMMHH

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName))BEGIN

   SELECT TOP 1
      @databaseName = d.database_name
     ,@backupPath = lss.backup_source_directory
     ,@monitorServer = lss.monitor_server
     ,@secondaryServer = lss.primary_server
     ,@secondaryDatabase = lss.primary_database
   FROM
      @databases AS d LEFT JOIN msdb.dbo.log_shipping_secondary AS lss ON (d.secondary_id = lss.secondary_id)
   ORDER BY
      d.database_name ASC;     
  
   PRINT N'USE msdb';
   PRINT N'';
   PRINT N'PRINT N''Beginning failover logshipping configuration on ' + quotename(@databaseName) + N''';';
   PRINT N'';
   PRINT N'DECLARE @LS_BackupJobId	AS uniqueidentifier'; 
   PRINT N'       ,@LS_PrimaryId	AS uniqueidentifier'; 
   PRINT N'       ,@SP_Add_RetCode	As int';
   PRINT N'';
   PRINT N'';
   PRINT N'EXEC @SP_Add_RetCode = master.dbo.sp_add_log_shipping_primary_database'; 
   PRINT N'   @database = N''' + @databaseName + N''''; 
   PRINT N'  ,@backup_directory = N''' + @backupPath + N'''';
   PRINT N'  ,@backup_share = N''' + @backupPath + N''''; 
   PRINT N'  ,@backup_job_name = N''LSBackup_' + @databaseName + N''''; 
   PRINT N'  ,@backup_retention_period = 4320';
   PRINT N'  ,@monitor_server = N''' + @monitorServer + N'''';
   PRINT N'  ,@monitor_server_security_mode = 1';
   PRINT N'  ,@backup_threshold = 60';
   PRINT N'  ,@threshold_alert_enabled = 1';
   PRINT N'  ,@history_retention_period = 5760';
   PRINT N'  ,@backup_job_id = @LS_BackupJobId OUTPUT';
   PRINT N'  ,@primary_id = @LS_PrimaryId OUTPUT';
   PRINT N'  ,@overwrite = 1';
   PRINT N'  ,@ignoreremotemonitor = 1';
   PRINT N'';
   PRINT N'';
   PRINT N'IF (@@ERROR = 0 AND @SP_Add_RetCode = 0)';
   PRINT N'BEGIN';
   PRINT N'';
   PRINT N'DECLARE @LS_BackUpScheduleUID	AS uniqueidentifier';
   PRINT N'DECLARE @LS_BackUpScheduleID	     AS int';
   PRINT N'';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_add_schedule';
   PRINT N'		   @schedule_name =N''LSBackupSchedule_' + lower(@@SERVERNAME) + N'1' + N''''; --The 1 is kept from the original configuration
   PRINT N'		   ,@enabled = 1';
   PRINT N'		   ,@freq_type = 4';
   PRINT N'		   ,@freq_interval = 1';
   PRINT N'		   ,@freq_subday_type = 4';
   PRINT N'		   ,@freq_subday_interval = 15';
   PRINT N'		   ,@freq_recurrence_factor = 0';
   PRINT N'		   ,@active_start_date = ' + @currentDate; 
   PRINT N'		   ,@active_end_date = 99991231';
   PRINT N'		   ,@active_start_time = 0';
   PRINT N'		   ,@active_end_time = 235900';
   PRINT N'		   ,@schedule_uid = @LS_BackUpScheduleUID OUTPUT';
   PRINT N'		   ,@schedule_id = @LS_BackUpScheduleID OUTPUT';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_attach_schedule';
   PRINT N'		   @job_id = @LS_BackupJobId';
   PRINT N'		   ,@schedule_id = @LS_BackUpScheduleID';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_update_job'; 
   PRINT N'		   @job_id = @LS_BackupJobId';
   PRINT N'		   ,@enabled = 1';
   PRINT N'';
   PRINT N'';
   PRINT N'ELSE';
   PRINT N'    ROLLBACK TRANSACTION';
   PRINT N'END'; 
   PRINT N'';
   PRINT N'';
   PRINT N'EXEC master.dbo.sp_add_log_shipping_primary_secondary';
   PRINT N'		   @primary_database = N''' + @databaseName + N'''';
   PRINT N'		   ,@secondary_server = N''' + @secondaryServer + N''''; 
   PRINT N'		   ,@secondary_database = N''' + @secondaryDatabase + N'''';
   PRINT N'		   ,@overwrite = 1';
   PRINT N'';

END;

PRINT N'';
PRINT N'COMMIT TRANSACTION;';
-- ****** End: Script to be run at Failover Primary ******

 




