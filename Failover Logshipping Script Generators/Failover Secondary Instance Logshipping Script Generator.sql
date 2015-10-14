/*

This script is ran on the original secondary instance after the secondary instance databases have been configured as failover primaries

Use this script to produce a T-SQL script to run on the primary instance you're failing over from to configure it as a seondary instance for the server you're failing over to

*/

--We won't be able to fully run this script until the secondary instance is set up as a primary instance

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

declare @databases table (
  database_name               nvarchar(128) not null primary key
 ,original_secondary          nvarchar(128)
 ,copy_job_id                 uniqueidentifier
 ,restore_job_id              uniqueidentifier
 ,backup_source_path          nvarchar(500) not null
 ,backup_destination_path     nvarchar(500) not null
 ,file_retention_period       int not null
 ,restore_delay               int not null
 ,restore_threshold           int not null
 ,history_retention_period    int not null
 ,threshold_alert_enabled     tinyint not null
 ,restore_mode                tinyint not null
 ,disconnect_users            tinyint not null
);

insert into @databases (
   database_name
  ,original_secondary
  ,copy_job_id
  ,restore_job_id
  ,backup_source_path
  ,backup_destination_path
  ,file_retention_period
  ,restore_delay
  ,restore_threshold
  ,history_retention_period
  ,threshold_alert_enabled
  ,restore_mode
  ,disconnect_users
)
select
    lsps.secondary_database AS database_name
   ,lss.copy_job_id AS copy_job_id
   ,lss.restore_job_id AS restore_job_id
   ,lss.backup_source_directory AS backup_source_path
   ,lss.backup_destination_directory AS backup_destination_path
   ,lss.file_retention_period AS file_retention_period
   ,lssd.secondary_database AS original_secondary
   ,lssd.restore_delay AS restore_delay
   ,lssd.restore_mode AS restore_mode
   ,lssd.disconnect_users AS disconnect_users
   ,lsms.restore_threshold AS restore_threshold
   ,lsms.history_retention_period AS history_retention_period
   ,lsms.threshold_alert_enabled AS threshold_alert_enabled
from
    log_shipping_primary_secondaries AS lsps LEFT JOIN log_shipping_secondary AS lss ON (lsps.secondary_database = lss.primary_database)
    LEFT JOIN log_shipping_secondary_databases AS lssd ON (lssd.secondary_id = lss.secondary_id)
    LEFT JOIN log_shipping_monitor_secondary AS lsms ON (lsms.secondary_id = lss.secondary_id)

--The join we usually do to sys.databases here to check if the db is online and such will have to be done within the outputted script since this is being ran
--on the primary instance where there isn't access to the state of the secondary instance's databases

where
    ((@databaseFilter is null) 
      or (lsps.secondary_database like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lsps.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   PRINT N'There are no secondary databases eligible to be configured for logshipping';

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

DECLARE @jobInfo AS TABLE(
              job_id                      uniqueidentifier not null primary key
             ,job_name                    nvarchar(128)
             ,target_database             nvarchar(128)
             ,freq_type                   int not null
             ,freq_interval               int not null
             ,freq_subday_type            int not null
             ,freq_subday_interval        int not null
             ,freq_recurrence_factor       int not null
)
INSERT INTO @jobInfo(
             job_id
            ,job_name
            ,target_database
            ,freq_type
            ,freq_interval
            ,freq_subday_type
            ,freq_subday_interval
            ,freq_recurrence_factor
)
SELECT 
    sj.job_id AS job_id
   ,sj.name AS job_name
   ,d.database_name AS target_database
   ,ss.freq_type AS freq_type
   ,ss.freq_interval AS freq_interval
   ,ss.freq_subday_type AS freq_subday_type
   ,ss.freq_subday_interval AS freq_subday_interval
   ,ss.freq_recurrence_factor AS freq_recurrence_factor
FROM
   @databases as d
   LEFT JOIN sysjobs as sj on (d.copy_job_id = sj.job_id OR d.restore_job_id = sj.job_id)
   LEFT JOIN sysjobschedules as sjs on (sj.job_id = sjs.job_id)
   LEFT JOIN sysschedules as ss on (sjs.schedule_id = ss.schedule_id)
   LEFT JOIN log_shipping_secondary as lss on (lss.primary_database = d.database_name) --this is for lss.primary_server in the outer apply

ORDER BY
   d.database_name ASC;

if (@debug = 1) begin

   select
      *
   from
      @jobInfo AS ji
   order by
      ji.target_database;

end;

DECLARE @databaseName               nvarchar(128)
       ,@backupSourcePath           nvarchar(500)
       ,@backupDestinationPath      nvarchar(500)
       ,@secondaryServer            nvarchar(128) --Since this script is ran on the failover primary, we can't use @@SERVERNAME to get the name of the failover secondary 
       ,@monitorServer              nvarchar(128)
       ,@maxDatabaseLen             int
       ,@maxPathLen                 int

SET @databaseName = N'';
SET @maxDatabaseLen = (SELECT MAX(datalength(d.database_name)) FROM @databases AS d);
SET @maxPathLen = (SELECT MAX(datalength(d.backup_source_path)) FROM @databases as d);

SELECT TOP 1
   @secondaryServer = lss.primary_server
  ,@monitorServer = lss.monitor_server
FROM 
   msdb.dbo.log_shipping_secondary AS lss;


--================================

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Use the following script to configure failover logshipping for the following databases as secondaries on ' + @secondaryServer + ' with backup source and destination paths:';
PRINT N'--';


WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@backupSourcePath = d.backup_source_path
     ,@backupDestinationPath = d.backup_destination_path
   FROM
      @databases AS d 
   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT N'--   ' + LEFT((@databaseName + replicate(' ', @maxDatabaseLen / 2)), @maxDatabaseLen / 2) + LEFT((@backupSourcePath + replicate(' ', @maxPathLen / 2)), @maxPathLen / 2) + @backupDestinationPath  ;

END;     

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
PRINT N'';
PRINT N'PRINT N''Beginning Logshipping Configurations...'';';
PRINT N'PRINT N'''';';
PRINT N'';

--
--End of setup, start logshipping 
--

DECLARE @originalSecondary          nvarchar(128)
       ,@fileRetentionPeriod        int
       ,@restoreDelay               int
       ,@restoreThreshold           int
       ,@historyRetentionPeriod     int
       ,@thresholdAlertEnabled      tinyint
       ,@restoreMode                tinyint
       ,@disconnectUsers            tinyint
       ,@freqType                   int
       ,@freqInterval               int
       ,@freqSubdayType             int
       ,@freqSubdayInterval         int
       ,@freqRecurrenceFactor       int
   
SET @databaseName = N'';

WHILE(EXISTS(SELECT * FROM @databases as d WHERE @databaseName > d.database_name))BEGIN

   SELECT TOP 1
       @databaseName = d.database_name
      ,@backupSourcePath = d.backup_source_path
      ,@backupDestinationPath = d.backup_destination_path
      ,@originalSecondary = d.original_secondary
      ,@fileRetentionPeriod = d.file_retention_period
      ,@restoreDelay = d.restore_delay
      ,@restoreThreshold = d.restore_threshold
      ,@historyRetentionPeriod = d.history_retention_period
      ,@thresholdAlertEnabled = d.threshold_alert_enabled
      ,@restoreMode = d.restore_mode
      ,@disconnectUsers = d.disconnect_users
      ,@freqType = ji.freq_type
      ,@freqInterval = ji.freq_interval
      ,@freqSubdayType = ji.freq_subday_type
      ,@freqSubdayInterval = ji.freq_subday_interval
      ,@freqRecurrenceFactor = ji.freq_recurrence_factor
   FROM
      @databases AS d LEFT JOIN @jobInfo AS ji ON (d.database_name = ji.target_database)
   WHERE 
      @databaseName > d.database_name
      AND ji.job_name LIKE '%Copy%'
   ORDER BY
      d.database_name ASC;

   PRINT N'PRINT N''Starting Logshipping for ' + @databaseName + N''';';
   PRINT N'';
   PRINT N'BEGIN TRANSACTION;';
   PRINT N'';
   PRINT N'DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier';
   PRINT N'DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier'; 
   PRINT N'DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier'; 
   PRINT N'DECLARE @LS_Add_RetCode	               As int'; 
   PRINT N'DECLARE @currentDate                   AS int';
   PRINT N'';
   PRINT N'SET @currentDate = CAST((convert(nvarchar(8), CURRENT_TIMESTAMP, 112) AS int); --YYYYMMHH';
   PRINT N'';
   PRINT N'EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary'; 
   PRINT N'         @primary_server = N''' + @@SERVERNAME + N'''';  
   PRINT N'        ,@primary_database = N''' + @originalSecondary + N'''';
   PRINT N'        ,@backup_source_directory = N''' + @backupSourcePath + N'''';
   PRINT N'        ,@backup_destination_directory = N''' + @backupDestinationPath + N''''; 
   PRINT N'        ,@copy_job_name = N''LSCopy_' + lower(@@SERVERNAME) + N'_' + @databaseName + N''''; 
   PRINT N'        ,@restore_job_name = N''LSRestore_' + lower(@@SERVERNAME) + N'_' + @databaseName + N''''; 
   PRINT N'        ,@file_retention_period = ' + @fileRetentionPeriod;
   PRINT N'        ,@monitor_server = N''' + @monitorServer + N'''';
   PRINT N'        ,@monitor_server_security_mode = 1';
   PRINT N'        ,@overwrite = 1';
   PRINT N'        ,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT';
   PRINT N'        ,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT';
   PRINT N'        ,@secondary_id = @LS_Secondary__SecondaryId OUTPUT';
   PRINT N'';
   PRINT N'IF (@@ERROR = 0 AND @LS_Add_RetCode = 0)'; 
   PRINT N'BEGIN'; 
   PRINT N'';
   PRINT N'DECLARE @LS_SecondaryCopyJobScheduleUID	As uniqueidentifier'; 
   PRINT N'DECLARE @LS_SecondaryCopyJobScheduleID	AS int'; 
   PRINT N'';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_add_schedule';
   PRINT N'          @schedule_name =N''DefaultCopyJobSchedule'''; 
   PRINT N'         ,@enabled = 1';
   PRINT N'         ,@freq_type = ' + @freqType; 
   PRINT N'	 	,@freq_interval = ' + @freqInterval; 
   PRINT N'	 	,@freq_subday_type = ' + @freqSubdayType; 
   PRINT N'	 	,@freq_subday_interval = ' + @freqSubdayInterval; 
   PRINT N'	 	,@freq_recurrence_factor = ' + @freqRecurrenceFactor;
   PRINT N'	 	,@active_start_date = @currentDate';
   PRINT N'	 	,@active_end_date = 99991231'; 
   PRINT N'	 	,@active_start_time = 0'; 
   PRINT N'	 	,@active_end_time = 235900'; 
   PRINT N'	 	,@schedule_uid = @LS_SecondaryCopyJobScheduleUID OUTPUT'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryCopyJobScheduleID OUTPUT'; 
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'	      @job_id = @LS_Secondary__CopyJobId ';
   PRINT N'	 	,@schedule_id = @LS_SecondaryCopyJobScheduleID '; 
   PRINT N'';
   PRINT N'DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier'; 
   PRINT N'DECLARE @LS_SecondaryRestoreJobScheduleID	AS int'; 

   --Get job info for the restore job

   SELECT TOP 1
       @freqType = ji.freq_type
      ,@freqInterval = ji.freq_interval
      ,@freqSubdayType = ji.freq_subday_type
      ,@freqSubdayInterval = ji.freq_subday_interval
      ,@freqRecurrenceFactor = ji.freq_recurrence_factor
   FROM
      @databases AS d LEFT JOIN @jobInfo AS ji ON (d.database_name = ji.target_database)
   WHERE 
      @databaseName > d.database_name
      AND ji.job_name LIKE '%Restore%'
   ORDER BY
      d.database_name ASC;

   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_add_schedule'; 
   PRINT N'		 @schedule_name =N''DefaultRestoreJobSchedule'; 
   PRINT N'	 	,@enabled = 1 ';
   PRINT N'         ,@freq_type = ' + @freqType; 
   PRINT N'	 	,@freq_interval = ' + @freqInterval; 
   PRINT N'	 	,@freq_subday_type = ' + @freqSubdayType; 
   PRINT N'	 	,@freq_subday_interval = ' + @freqSubdayInterval; 
   PRINT N'	 	,@freq_recurrence_factor = ' + @freqRecurrenceFactor;
   PRINT N'	 	,@active_start_date = @currentDate';
   PRINT N'	 	,@active_end_date = 99991231 ';
   PRINT N'	 	,@active_start_time = 0 ';
   PRINT N'	 	,@active_end_time = 235900 ';
   PRINT N'	 	,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT ';
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'		 @job_id = @LS_Secondary__RestoreJobId'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryRestoreJobScheduleID '; 
   PRINT N'';
   PRINT N'ELSE';
   PRINT N'    ROLLBACK TRANSACTION;'
   PRINT N'END'; 
   PRINT N'';
   PRINT N'';
   PRINT N'DECLARE @LS_Add_RetCode2	As int';
   PRINT N'';
   PRINT N'';
   PRINT N'IF (@@ERROR = 0 AND @LS_Add_RetCode = 0)';
   PRINT N'BEGIN';
   PRINT N'';
   PRINT N'EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database'; 
   PRINT N'	      @secondary_database = N''' + @databaseName + N''''; 
   PRINT N'	 	,@primary_server = N''' + @@SERVERNAME + N'''';
   PRINT N'	 	,@primary_database = N''' + @originalSecondary + N'''';
   PRINT N'	 	,@restore_delay = ' + @restoreDelay;
   PRINT N'	 	,@restore_mode = ' + @restoreMode; 
   PRINT N'	 	,@disconnect_users	= ' + @disconnectUsers;
   PRINT N'	 	,@restore_threshold = ' + @restoreThreshold;
   PRINT N'	 	,@threshold_alert_enabled = ' + @thresholdAlertEnabled;
   PRINT N'	 	,@history_retention_period = ' + @historyRetentionPeriod;
   PRINT N'	 	,@overwrite = 1';
   PRINT N'	 	,@ignoreremotemonitor = 1';
   PRINT N'';
   PRINT N'ELSE';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'END'; 
   PRINT N'';
   PRINT N'';
   PRINT N'IF (@@error = 0 AND @LS_Add_RetCode = 0)'; 
   PRINT N'BEGIN'; 
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_update_job'; 
   PRINT N'		 @job_id = @LS_Secondary__CopyJobId'; 
   PRINT N'	 	,@enabled = 1'; 
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_update_job'; 
   PRINT N'		 @job_id = @LS_Secondary__RestoreJobId'; 
   PRINT N'	 	,@enabled = 1';
   PRINT N'';
   PRINT N'ELSE';
   PRINT N'    ROLLBACK TRANSACTION;';
   PRINT N'END';
   PRINT N'';
END; 

PRINT N'COMMIT TRANSACITON;';