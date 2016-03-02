/*

This script is ran on the primary server of your logshipping configuration

Use this script to produce a T-SQL script to setup the logshipping secondary instance

*/

set nocount on;
go

use msdb;
go

declare  @databaseFilter            nvarchar(128)
       , @debug                     bit
       , @exclude_system            bit;

set @debug = 1;

--set @databaseFilter = N'Footprints';

--================================

--if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\'; We're not appending to this


--
--Configuring logshipping involves setting up a number of variables.
--Many of the variables used when setting up the secondary instances are also used when configuring the primary instances. Any applicable values will be copied over from
--each secondary's respective primary instance via @primaryDefaults
--

declare @primaryDefaults table (
   primary_id                    uniqueidentifier not null primary key clustered
  ,database_name                 nvarchar(128) not null 
  ,backup_source_directory       nvarchar(500) not null
  ,file_retention_period         int not null
  ,monitor_server                sysname not null
  ,monitor_server_security_mode  bit not null
  ,restore_threshold             int not null
  ,threshold_alert_enabled       bit not null
  ,history_retention_period      int not null
  ,freq_type                     int not null
  ,freq_interval                 int not null
  ,freq_subday_type              int not null
  ,freq_subday_interval          int not null
  ,freq_recurrence_factor        int not null
  ,active_start_date             int not null
  ,active_end_date               int not null
  ,active_start_time             int not null
  ,active_end_time               int not null
);

INSERT INTO @primaryDefaults

SELECT 
   lsmp.primary_id AS primary_id
  ,lsmp.primary_database AS database_name
  ,lspd.backup_directory AS backup_source_directory
  ,lspd.backup_retention_period AS file_retention_period
  ,lspd.monitor_server AS monitor_server
  ,lspd.monitor_server_security_mode AS monitor_server_security_mode
  ,lsmp.backup_threshold AS restore_threshold
  ,lsmp.threshold_alert_enabled AS threshold_alert_enabled
  ,lsmp.history_retention_period AS history_retention_period
  ,ss.freq_type AS freq_type
  ,ss.freq_interval AS freq_interval
  ,ss.freq_subday_type AS freq_subday_type
  ,ss.freq_subday_interval AS freq_subday_interval
  ,ss.freq_recurrence_factor AS freq_recurrence_factor
  ,ss.active_start_date AS active_start_date
  ,ss.active_end_date AS active_end_date
  ,ss.active_start_time AS active_start_time
  ,ss.active_end_time AS active_end_time
FROM 
   log_shipping_monitor_primary AS lsmp INNER JOIN log_shipping_primary_databases AS lspd ON (lsmp.primary_id = lspd.primary_id)
   INNER JOIN sysjobschedules AS sjs ON (lspd.backup_job_id = sjs.job_id)
   INNER JOIN sysschedules AS ss ON (sjs.schedule_id = ss.schedule_id)
ORDER BY
   lsmp.primary_database ASC;


if not exists(select * from @primaryDefaults)
   raiserror('There are no databases eligible to be configured for logshipping', 17, -1);

if (@debug = 1) begin

   select
      *
   from
      @primaryDefaults AS pd
   order by
      pd.database_name;

end;

/*
For the values unique to configuring the secondary instance, you can setup defaults here that will be applied to all of the database logshipping configurations.
Then you can change the values for specific databases that require unique values in the output script.
The variables (that can) will initially be set to the default values as Microsoft sets them when they generate a logshipping script
The rest will require input on your part and will be tagged with a #INSERT

Since this script is being ran on the primary server, we can't find the backup location for the logs through the registry. This will instead be done within the output script.
*/

DECLARE   @secondaryServer          SYSNAME
         ,@copy_job_name            SYSNAME
         ,@restore_job_name         SYSNAME
         ,@copy_schedule_name       NVARCHAR(128)
         ,@restore_schedule_name    NVARCHAR(128)
         ,@overwrite                BIT 
         ,@ignoreremotemonitor      BIT 
         ,@enabled                  TINYINT
         ,@restore_delay            INT
         ,@restore_all              BIT
         ,@restore_mode             BIT
         ,@disconnect_users         BIT;
         
--
-- Set Defaults 
--

-- We join to @primaryDefaults in the case that there is a database on a separate logshipping configuration so that we exclude it

SELECT TOP 1 @secondaryServer = lsps.secondary_server FROM log_shipping_primary_secondaries AS lsps INNER JOIN @primaryDefaults AS pd ON (lsps.primary_id = pd.primary_id);

SET @copy_job_name = N'LSCopy_' + LOWER(@@SERVERNAME) + N'_';       -- Default is LSCopy_primaryServerName_databaseName. The full string is defined within the script. This variable functions as a prefix to the database name
SET @restore_job_name = N'LSRestore_' + LOWER(@@SERVERNAME) + N'_'; -- Default is LSRestore_primaryServerName_databaseName. The full string is defined within the script. This variable functions as a prefix to the database name
SET @copy_schedule_name = N'LSCopySchedule_' + @secondaryServer + N'1'        -- Name does not have to be unique
SET @restore_schedule_name = N'LSRestoreSchedule_' + @secondaryServer + N'1'  -- Name does not have to be unique
SET @overwrite = 1;              -- Whether or not to overwrite a previous logship config for this instance, 1 = overwrite
SET @ignoreremotemonitor = 1;    -- Whether or not to try and use the linked server to configure the monitor from the secondary server (Hasn't worked in testing), 1 = ignore (Manually run script on monitor server)
SET @enabled = 1                 -- Whether or not jobs will run on their schedules once configuration has finished. 1 = Run 
SET @restore_delay = 0;          -- The amount of time, in minutes, that the secondary server waits before restoring a given backup
SET @restore_all = 1;            -- 1 = Restore all available transaction logs for a database when restoring. 0 = Restore 1 log for a database then quit.
SET @restore_mode = 0;           -- 0 = NORECOVERY, 1 = STANDBY
SET @disconnect_users = 0;       -- Whether or not to disconnect users from the secondary DB during a restore operation. 0 = yes, 1 = no

--
-- End of default values setup
--

--@primaryDefault Variables

DECLARE @databaseName               NVARCHAR(128)
       ,@backupSourceDirectory      NVARCHAR(500)
       ,@fileRetentionPeriod        NVARCHAR(10)
       ,@monitorServer              NVARCHAR(128)
       ,@monitorServerSecurityMode  NVARCHAR(1)
       ,@restoreThreshold           NVARCHAR(10)
       ,@thresholdAlertEnabled      NVARCHAR(1)
       ,@historyRetentionPeriod     NVARCHAR(10)
       ,@freqType                   NVARCHAR(10)
       ,@freqInterval               NVARCHAR(10)
       ,@freqSubdayType             NVARCHAR(10)
       ,@freqSubdayInterval         NVARCHAR(10)
       ,@freqRecurrenceFactor       NVARCHAR(10)
       ,@activeStartDate            NVARCHAR(8)
       ,@activeEndDate              NVARCHAR(8)
       ,@activeStartTime            NVARCHAR(6)
       ,@activeEndTime              NVARCHAR(6)
       ;

SET @databaseName = N'';

PRINT N'/*';
PRINT N'*****RUN ON ' + quotename(@secondaryServer) + N'*****';
PRINT N'Use the following script to configure the following databases as logshipping secondaries on ' + quotename(@secondaryServer) + N':';
PRINT N'';

WHILE EXISTS(SELECT * FROM @primaryDefaults AS d WHERE d.database_name > @databaseName) BEGIN
   
   SELECT TOP 1 
      @databaseName = database_name 
   FROM 
      @primaryDefaults 
   WHERE 
      database_name > @databaseName 
   ORDER BY 
   database_name ASC;
  
   PRINT quotename(@databaseName); 

END;     

PRINT N'';
PRINT N'With the following secondary-specific logshipping defaults:';
PRINT N'';
PRINT N'Copy Jobs'' Schedule Name: ' + @copy_schedule_name;
PRINT N'Restore Jobs'' Schedule Name: ' + @restore_schedule_name;
PRINT N'Overwrite Pre-Existing Logshipping Configurations: ' + CAST(@overwrite AS VARCHAR) + N'  --0 = Don''t Overwrite, 1 = Overwrite';
PRINT N'Manually Run Secondary Monitor Script: ' + CAST(@ignoreremotemonitor AS VARCHAR) + N'  --0 = Configure through linked server, 1 = Manually Run';
PRINT N'Schedules Enabled: ' + CAST(@enabled AS VARCHAR);
PRINT N'Restore Delay In Minutes: ' + CAST(@restore_delay AS VARCHAR);
PRINT N'Restore All Setting: ' + CAST(@restore_all AS VARCHAR) + N'  --1 = Restore All availabe logs for a database, 0 = Restore 1 log then quit';
PRINT N'Restore Mode: ' + CAST(@restore_mode AS VARCHAR) + N'  --0 = NORECOVERY, 1 = STANDBY';
PRINT N'Disconnect Users During Restore: '+ CAST(@disconnect_users AS VARCHAR) + N'  --0 = yes, 1 = no';
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
PRINT N'PRINT N''Beginning Secondary Logshipping Configurations...'';';
PRINT N'PRINT N'''';';
PRINT N'';
PRINT N'DECLARE @backupDestinationFilePath NVARCHAR(500);'
PRINT N'';
PRINT N'EXEC xp_instance_regread';
PRINT N'   @rootkey    = ''HKEY_LOCAL_MACHINE''';
PRINT N' , @key        = ''Software\Microsoft\MSSQLServer\MSSQLServer''';
PRINT N' , @value_name = ''BackupDirectory''';
PRINT N' , @value      = @backupDestinationFilePath OUTPUT;';
PRINT N'';
PRINT N'--The destination for the log backups that the copy job retrieves is by default determined by the local registry via xp_instance_regread above.'
PRINT N'--If you''d like to provide another default file path, uncomment the following SET statement to override the location provided by the registry.';
PRINT N'--SET @backupDestinationFilePath = ;';
PRINT N'';
PRINT N'-- #elapsedTimeAndFilePath is used to keep track of the total execution time of the script, along with holding the backup destination file path across batches ';
PRINT N'';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#elapsedTimeAndFilePath'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #elapsedTimeAndFilePath';
PRINT N'';
PRINT N'CREATE TABLE #elapsedTimeAndFilePath (timestamps DATETIME, file_path NVARCHAR(500));';
PRINT N'';
PRINT N'INSERT INTO #elapsedTimeAndFilePath SELECT CURRENT_TIMESTAMP, @backupDestinationFilePath;';
PRINT N'';

SET @databaseName = N'';
raiserror('',0,1) WITH NOWAIT; --flush print buffer

WHILE EXISTS(SELECT TOP 1 * FROM @primaryDefaults WHERE database_name > @databaseName ORDER BY database_name ASC)BEGIN

 SELECT TOP 1
      @databaseName = database_name
     ,@backupSourceDirectory = backup_source_directory
     ,@fileRetentionPeriod = file_retention_period
     ,@monitorServer = monitor_server
     ,@monitorServerSecurityMode = monitor_server_security_mode
     ,@restoreThreshold = restore_threshold
     ,@thresholdAlertEnabled = threshold_alert_enabled
     ,@historyRetentionPeriod = history_retention_period
     ,@freqType = freq_type
     ,@freqInterval = freq_interval
     ,@freqSubdayType = freq_subday_type
     ,@freqSubdayInterval = freq_subday_interval
     ,@freqRecurrenceFactor = freq_recurrence_factor
     ,@activeStartDate = active_start_date
     ,@activeEndDate = active_end_date
     ,@activeStartTime = active_start_time
     ,@activeEndTime = active_end_time
   FROM
      @primaryDefaults 
   WHERE 
      database_name > @databaseName
   ORDER BY 
      database_name ASC;

   PRINT N'GO';
   PRINT N'';
   PRINT N'PRINT N'''';';
   PRINT N'';
   PRINT N'--********Secondary Logshipping for ' + quotename(@databaseName) + N'********--';
   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'';  
   PRINT N'    PRINT N''=================================='';';
   PRINT N'    PRINT N''Beginning secondary logshipping configuration for ' + quotename(@databaseName) + N''';';
   PRINT N'';
   PRINT N'';
   PRINT N'	DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier ';
   PRINT N'	DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier ';
   PRINT N'	DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier ';
   PRINT N'	DECLARE @LS_Add_RetCode	As int ';
   PRINT N'    DECLARE @backupDestinationFilePath AS NVARCHAR(500)';
   PRINT N'';
   PRINT N'    SELECT TOP 1 @backupDestinationFilePath = file_path FROM #elapsedTimeAndFilePath;';
   PRINT N'';
   PRINT N'';
   PRINT N'	EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary ';
   PRINT N'			 @primary_server = N''' + @@SERVERNAME + N'''';
   PRINT N'			,@primary_database = N''' + @databaseName + N'''';
   PRINT N'			,@backup_source_directory = @backupDestinationFilePath';
   PRINT N'			,@backup_destination_directory = @backupDestinationFilePath';
   PRINT N'			,@copy_job_name = N''' + @copy_job_name + @databaseName + N''''; 
   PRINT N'			,@restore_job_name = N''' + @restore_job_name + @databaseName + N'''';
   PRINT N'			,@file_retention_period = ' + @fileRetentionPeriod;
   PRINT N'			,@monitor_server = N''' + @monitorServer + N'''';
   PRINT N'			,@monitor_server_security_mode = ' + @monitorServerSecurityMode;
   PRINT N'			,@overwrite = ' + CAST(@overwrite AS VARCHAR);
   PRINT N'			,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT ';
   PRINT N'			,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT ';
   PRINT N'			,@secondary_id = @LS_Secondary__SecondaryId OUTPUT ';
   PRINT N'';
   PRINT N'	IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) ';
   PRINT N'	BEGIN ';
   PRINT N'';
   PRINT N'		DECLARE @LS_SecondaryCopyJobScheduleUID	As uniqueidentifier ';
   PRINT N'	     DECLARE @LS_SecondaryCopyJobScheduleID	AS int ';
   PRINT N'';
   PRINT N'';
   PRINT N'		EXEC msdb.dbo.sp_add_schedule ';
   PRINT N'				@schedule_name =N''' + @copy_schedule_name + N'''';
   PRINT N'				,@enabled = ' + CAST(@enabled AS VARCHAR);
   PRINT N'				,@freq_type = ' + @freqType;
   PRINT N'				,@freq_interval = ' + @freqInterval;
   PRINT N'				,@freq_subday_type = ' + @freqSubdayType;
   PRINT N'				,@freq_subday_interval = ' + @freqSubdayInterval;
   PRINT N'				,@freq_recurrence_factor = ' + @freqRecurrenceFactor;
   PRINT N'				,@active_start_date = ' + @activeStartDate;
   PRINT N'				,@active_end_date = ' + @activeEndDate;
   PRINT N'				,@active_start_time = ' + @activeStartTime;
   PRINT N'				,@active_end_time = ' + @activeEndTime;
   PRINT N'				,@schedule_uid = @LS_SecondaryCopyJobScheduleUID OUTPUT ';
   PRINT N'				,@schedule_id = @LS_SecondaryCopyJobScheduleID OUTPUT ';
   PRINT N'';
   PRINT N'		EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'				@job_id = @LS_Secondary__CopyJobId ';
   PRINT N'				,@schedule_id = @LS_SecondaryCopyJobScheduleID  ';
   PRINT N'';
   PRINT N'		DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier ';
   PRINT N'		DECLARE @LS_SecondaryRestoreJobScheduleID	AS int ';
   PRINT N'';
   PRINT N'';
   PRINT N'		EXEC msdb.dbo.sp_add_schedule ';
   PRINT N'				@schedule_name =N''' + @restore_schedule_name + N'''';
   PRINT N'				,@enabled = ' + CAST(@enabled AS VARCHAR);
   PRINT N'				,@freq_type = ' + @freqType;
   PRINT N'				,@freq_interval = ' + @freqInterval;
   PRINT N'				,@freq_subday_type = ' + @freqSubdayType;
   PRINT N'				,@freq_subday_interval = ' + @freqSubdayInterval;
   PRINT N'				,@freq_recurrence_factor = ' + @freqRecurrenceFactor;
   PRINT N'				,@active_start_date = ' + @activeStartDate;
   PRINT N'				,@active_end_date = ' + @activeEndDate;
   PRINT N'				,@active_start_time = ' + @activeStartTime;
   PRINT N'				,@active_end_time = ' + @activeEndTime;
   PRINT N'				,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT ';
   PRINT N'				,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT ';
   PRINT N'';
   PRINT N'		EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'				@job_id = @LS_Secondary__RestoreJobId ';
   PRINT N'				,@schedule_id = @LS_SecondaryRestoreJobScheduleID  ';
   PRINT N'';
   PRINT N'';
   PRINT N'	END ';
   PRINT N'    ELSE BEGIN';
   PRINT N'        RAISERROR(N''There was an issue while executing [master.dbo.sp_add_log_shipping_secondary_primary] for %s. Throwing error...'',11,1,N''' + quotename(@databaseName) + N''') WITH NOWAIT;';
   PRINT N'    END;';
   PRINT N'';
   PRINT N'';
   PRINT N'	DECLARE @LS_Add_RetCode2	As int ';
   PRINT N'';
   PRINT N'';
   PRINT N'	IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) ';
   PRINT N'	BEGIN ';
   PRINT N'';
   PRINT N'		EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database ';
   PRINT N'				 @secondary_database = N''' + @databaseName + N'''';
   PRINT N'				,@primary_server = N''' + @secondaryServer + N'''';
   PRINT N'				,@primary_database = N''' + @databaseName + N'''';
   PRINT N'				,@restore_delay = ' + CAST(@restore_delay AS VARCHAR);
   PRINT N'				,@restore_mode = ' + CAST(@restore_mode AS VARCHAR);
   PRINT N'				,@disconnect_users	= ' + CAST(@disconnect_users AS VARCHAR);
   PRINT N'				,@restore_threshold = ' + @restoreThreshold;
   PRINT N'				,@threshold_alert_enabled = ' + @thresholdAlertEnabled;
   PRINT N'				,@history_retention_period = ' + @historyRetentionPeriod;
   PRINT N'				,@overwrite = ' + CAST(@overwrite AS VARCHAR);
   PRINT N'				,@ignoreremotemonitor = ' + CAST(@ignoreremotemonitor AS VARCHAR);
   PRINT N'';
   PRINT N'';
   PRINT N'	END ';
   PRINT N'    ELSE BEGIN';
   PRINT N'        RAISERROR(N''There was an issue while configuring the job schedules for %s. Throwing error...'',11,1,N''' + quotename(@databaseName) + N''') WITH NOWAIT;';
   PRINT N'    END;';
   PRINT N'';
   PRINT N'';
   PRINT N'	IF (@@error = 0 AND @LS_Add_RetCode = 0) ';
   PRINT N'	BEGIN ';
   PRINT N'';
   PRINT N'	   EXEC msdb.dbo.sp_update_job ';
   PRINT N'			  @job_id = @LS_Secondary__CopyJobId ';
   PRINT N'			  ,@enabled = 1 ';
   PRINT N'';
   PRINT N'	   EXEC msdb.dbo.sp_update_job ';
   PRINT N'			  @job_id = @LS_Secondary__RestoreJobId ';
   PRINT N'			  ,@enabled = 1 ';
   PRINT N'';
   PRINT N'	END ';
   PRINT N'    ELSE BEGIN';
   PRINT N'        RAISERROR(N''There was an issue while executing [master.dbo.sp_add_log_shipping_secondary_database] for %s. Throwing error...'',11,1,N''' + quotename(@databaseName) + N''') WITH NOWAIT;';
   PRINT N'    END;';
   PRINT N'';
   PRINT N'    PRINT N''' + quotename(@databaseName) + N' successfully configured as a logshipping secondary.'';';
   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N'''';';
   PRINT N'    PRINT N''There was an issue configuring logshipping for ' + quotename(@databaseName) + N'. Quitting batch execution and cleaning up artifacts...'';';
   PRINT N'    PRINT N'''';';
   PRINT N'';
   PRINT N'    SELECT';
   PRINT N'        ERROR_NUMBER() AS ErrorNumber,'
   PRINT N'        ERROR_SEVERITY() AS ErrorSeverity,'
   PRINT N'        ERROR_STATE() as ErrorState,'
   PRINT N'        ERROR_PROCEDURE() as ErrorProcedure,'
   PRINT N'        ERROR_LINE() as ErrorLine,'
   PRINT N'        ERROR_MESSAGE() as ErrorMessage;'
   PRINT N'';
   PRINT N'    --Clean up artifacts';
   PRINT N'';
   PRINT N'    DELETE FROM log_shipping_secondary_databases WHERE secondary_database = N''' + @databaseName + N''';';
   PRINT N'    DELETE FROM log_shipping_monitor_secondary WHERE secondary_database = N''' + @databaseName + N''';';
   PRINT N'    IF (@LS_Secondary__SecondaryId IS NOT NULL)';
   PRINT N'       DELETE FROM log_shipping_secondary WHERE secondary_id = @LS_Secondary__SecondaryId';
   PRINT N'    IF (@LS_Secondary__CopyJobId IS NOT NULL)';
   PRINT N'       EXEC sp_delete_job @job_id = @LS_Secondary__CopyJobId';
   PRINT N'    IF (@LS_Secondary__RestoreJobId IS NOT NULL)';
   PRINT N'       EXEC sp_delete_job @job_id = @LS_Secondary__RestoreJobId';
   PRINT N'';
   PRINT N'    RETURN;';
   PRINT N'END CATCH';
   PRINT N'';

   raiserror('',0,1) WITH NOWAIT; --flush print buffer

END

PRINT N'GO';
PRINT N'';
PRINT N'--Print elapsed time';
PRINT N'';
PRINT N'DECLARE @startTime DATETIME;';
PRINT N'SELECT TOP 1 @startTime = timestamps FROM #elapsedTimeAndFilePath;';
PRINT N'';
PRINT N'PRINT N''Total Elapsed Time: '' +  STUFF(CONVERT(NVARCHAR(12), CURRENT_TIMESTAMP - @startTime, 14), 9, 1, ''.''); --hh:mi:ss.mmm';
PRINT N'';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''*****Secondary Logshipping of databases on ' + quotename(@secondaryServer) + N' complete. Continue to Secondary Monitor Logshipping*****'';';
PRINT N'';
PRINT N'DROP TABLE #elapsedTimeAndFilePath';

--End of script, proceed to Secondary Monitor Logshipping