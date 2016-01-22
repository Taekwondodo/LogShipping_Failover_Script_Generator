/*

This script is ran on the primary server of your logshipping configuration

Use this script to produce a T-SQL script to setup the logshipping secondary instance

*/

set nocount on;
go

use msdb;
go

declare  @databaseFilter nvarchar(128)
       , @debug          bit
       , @exclude_system bit;

set @debug = 1;

--set @databaseFilter = N'Footprints';

--================================

--if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\'; We're not appending to this

use msdb

-- @primaryDefaults takes information from the primary LS instance configurations that can be copied over to their respective secondary instances

declare @primaryDefaults table (
   database_name                 nvarchar(128) not null primary key clustered
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
  ,freq_relative_interval        int not null
  ,freq_recurrence_factor        int not null
  ,active_start_date             int not null
  ,active_end_date               int not null
  ,active_start_time             int not null
  ,active_end_time               int not null
);

INSERT INTO @primaryDefaults

SELECT 
   lsmp.primary_database AS database_name
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
  ,ss.freq_relative_interval AS freq_relative_interval
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
Configuring logshipping involves setting up a number of variables.
Many of the variables used when setting up the secondary instances are also used when configuring the primary instance. Any applicable values will be copied over from
the primary instance via @primaryDefaults

For the values unique to configuring the secondary instance, you can setup defaults here that will be applied to all of the database logshipping configurations.
Then you can change the values for specific databases that require unique values in the output script.
The variables (that can) will initially be set to the default values as Microsoft sets them when they generate a logshipping script
The rest will require input on your part and will be tagged with a #INSERT
*/

DECLARE  @backup_destination_directory NVARCHAR(500), 
         @copy_job_name                SYSNAME,
         @restore_job_name             SYSNAME, 
         @overwrite                    BIT, 
         @ignoreremotemonitor          BIT, 
         @enabled                      TINYINT, 
--
-- Set Defaults 
--

SET @backup_destination_directory = ; --Where the copy job will save the logs it copies from the primary instance
SET @copy_job_name = N'LSCopy_';       -- Default is LSCopy_serverName_databaseName. The full string is defined within the script. This variable functions as a prefix to the database name
SET @restore_job_name = N'LSRestore_'; -- Default is LSRestore_serverName_databaseName. The full string is defined within the script. This variable functions as a prefix to the database name
SET @overwrite = 1;                   --Whether or not to overwrite a previous logship config for this instance
SET @ignoreremotemonitor = 1;         --Whether or not to try and use the linked server to configure the monitor from the secondary server (Hasn't worked in testing)
SET @enabled = 1 --Whether or not jobs will run on their schedules once configuration has finished.

--
-- End of Defaults setup
--

Declare @databaseName NVARCHAR(128)

SET @databaseName = N'';

PRINT N'/*';
PRINT N'*****RUN ON ' + quotename(@@SERVERNAME) + N'*****';
PRINT N'Use the following script to configure the following databases as logshipping primaries on ' + quotename(@@SERVERNAME) + N':';
PRINT N'';

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name
   FROM
      @databases AS d 
   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT quotename(@databaseName);

END;     

PRINT N'';
PRINT N'With the following logshipping defaults:';
PRINT N'';
PRINT N'Secondary Server: ' + @secondary_server;
PRINT N'Monitor Server: ' +  @monitor_server;
PRINT N'Backup Directory: ' + @backup_directory;
PRINT N'Backup Share: ' + @backup_share;
PRINT N'Backup Retention Period: ' + CAST(@backup_retention_period AS VARCHAR);
PRINT N'Monitor Server Security Mode: ' + CAST(@monitor_server_security_mode AS VARCHAR);
PRINT N'Backup Threshold: ' + CAST(@backup_threshold AS VARCHAR);
PRINT N'Threshold Alert Enabled: ' + CAST(@threshold_alert_enabled AS VARCHAR);
PRINT N'History Retention Period ' + CAST(@history_retention_period AS VARCHAR);
PRINT N'Overwrite Pre-Existing Logshipping Configurations: ' + CAST(@overwrite AS VARCHAR);
PRINT N'Manually Run Primary Monitor Script: ' + CAST(@ignoreremotemonitor AS VARCHAR);
PRINT N'';
PRINT N'And the following job schedule defaults (https://msdn.microsoft.com/en-us/library/ms187320.aspx for reference):';
PRINT N'';
PRINT N'Schedule Name: ' + @schedule_name;
PRINT N'Schedule Enabled: ' + CAST(@enabled AS VARCHAR);
PRINT N'Frequency Type: ' + CAST(@freq_type AS VARCHAR);
PRINT N'Frequenty Interval: ' + CAST(@freq_interval AS VARCHAR);
PRINT N'Frequency Subday Type: ' + CAST(@freq_subday_type AS VARCHAR);
PRINT N'Frequency Subday Interval: ' + CAST(@freq_subday_interval AS VARCHAR);
PRINT N'Frequency Relative Interval: ' + CAST(@freq_relative_interval AS VARCHAR);
PRINT N'Frequency Recurrence Factor: ' + CAST(@freq_recurrence_factor AS VARCHAR);
PRINT N'Active Start Date: ' + CAST(@active_start_date AS VARCHAR);
PRINT N'Active End Date: ' + CAST(@active_end_date AS VARCHAR);
PRINT N'Active Start Time: ' + CAST(@active_start_time AS VARCHAR);
PRINT N'Active End Time: ' + CAST(@active_end_time AS VARCHAR);

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
PRINT N'PRINT N''Beginning Logshipping Configurations...'';';
PRINT N'PRINT N'''';';
PRINT N'';
PRINT N'-- #elapsedTime is used to keep track of the total execution time of the script';
PRINT N'';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#elapsedTime'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #elapsedTime';
PRINT N'';
PRINT N'CREATE TABLE #elapsedTime (timestamps datetime);';
PRINT N'INSERT INTO #elapsedTime SELECT CURRENT_TIMESTAMP;';

SET @databaseName = N'';
raiserror('',0,1) WITH NOWAIT; --flush print buffer

WHILE EXISTS(SELECT TOP 1 * FROM @databases WHERE database_name > @databaseName ORDER BY database_name ASC)BEGIN

   SELECT TOP 1 
      @databaseName = database_name 
   FROM 
      @databases 
   WHERE 
      database_name > @databaseName 
   ORDER BY 
   database_name ASC;

   PRINT N'--********Primary Logshipping for ' + quotename(@databaseName) + N'********--';
   PRINT N'';
   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'';  
   PRINT N'    PRINT N''=================================='';';
   PRINT N'    PRINT N''Beginning primary logshipping configuration on ' + quotename(@databaseName) + N''';';
   PRINT N'';
   PRINT N'    DECLARE @LS_BackupJobId           AS uniqueidentifier'; 
   PRINT N'           ,@LS_PrimaryId           AS uniqueidentifier'; 
   PRINT N'           ,@SP_Add_RetCode           As int';
   PRINT N'           ,@currentDate           AS int --Needs to be YYYYMMHH format';
   PRINT N'           ,@LS_BackUpScheduleUID  AS uniqueidentifier';
   PRINT N'           ,@LS_BackUpScheduleID   AS int';
   PRINT N'';
   PRINT N'    SET @currentDate = cast((convert(nvarchar(8), CURRENT_TIMESTAMP, 112)) as int); --YYYYMMHH';
   PRINT N'';
   PRINT N'    EXEC @SP_Add_RetCode = master.dbo.sp_add_log_shipping_primary_database'; 
   PRINT N'       @database = N''' + @databaseName + N''''; 
   PRINT N'      ,@backup_directory = N''' + @backup_directory + N'''';
   PRINT N'      ,@backup_share = N''' + @backup_share + N''''; 
   PRINT N'      ,@backup_job_name = N''' + @backup_job_name + @databaseName + N''''; 
   PRINT N'      ,@backup_retention_period = ' + CAST(@backup_retention_period  AS VARCHAR);
   PRINT N'      ,@monitor_server = N''' + @monitor_server + N'''';
   PRINT N'      ,@monitor_server_security_mode = ' + CAST(@monitor_server_security_mode AS VARCHAR);
   PRINT N'      ,@backup_threshold = ' + CAST(@backup_threshold AS VARCHAR);
   PRINT N'      ,@threshold_alert_enabled = ' + CAST(@threshold_alert_enabled AS VARCHAR);
   PRINT N'      ,@history_retention_period = ' + CAST(@history_retention_period AS VARCHAR);
   PRINT N'      ,@backup_job_id = @LS_BackupJobId OUTPUT';
   PRINT N'      ,@primary_id = @LS_PrimaryId OUTPUT';
   PRINT N'      ,@overwrite = ' + CAST(@overwrite AS VARCHAR);
   PRINT N'      ,@ignoreremotemonitor = ' + CAST(@ignoreremotemonitor AS VARCHAR);
   PRINT N'';
   PRINT N'';
   PRINT N'    IF (@@ERROR = 0 AND @SP_Add_RetCode = 0)';
   PRINT N'    BEGIN';
   PRINT N'';
   PRINT N'        SET @LS_BackUpScheduleUID = NULL';
   PRINT N'        SET @LS_BackUpScheduleID = NULL'; 
   PRINT N'';
   PRINT N'';
   PRINT N'        EXEC msdb.dbo.sp_add_schedule';
   PRINT N'                   @schedule_name = N''' + @schedule_name + N''''; 
   PRINT N'                   ,@enabled = ' + CAST(@enabled as VARCHAR);
   PRINT N'                   ,@freq_type = ' + CAST(@freq_type AS VARCHAR);
   PRINT N'                   ,@freq_interval = ' + CAST(@freq_interval AS VARCHAR);
   PRINT N'                   ,@freq_subday_type = ' + CAST(@freq_subday_type AS VARCHAR);
   PRINT N'                   ,@freq_subday_interval = ' + CAST(@freq_subday_interval AS VARCHAR);
   PRINT N'                   ,@freq_recurrence_factor = ' + CAST(@freq_recurrence_factor AS VARCHAR);
   PRINT N'                   ,@active_start_date = ' + CAST(@active_start_date AS VARCHAR); 
   PRINT N'                   ,@active_end_date = ' + CAST(@active_end_date AS VARCHAR);
   PRINT N'                   ,@active_start_time = ' + CAST(@active_start_time AS VARCHAR);
   PRINT N'                   ,@active_end_time = ' + CAST(@active_end_time AS VARCHAR);
   PRINT N'                   ,@schedule_uid = @LS_BackUpScheduleUID OUTPUT';
   PRINT N'                   ,@schedule_id = @LS_BackUpScheduleID OUTPUT';
   PRINT N'';
   PRINT N'        EXEC msdb.dbo.sp_attach_schedule';
   PRINT N'                   @job_id = @LS_BackupJobId';
   PRINT N'                   ,@schedule_id = @LS_BackUpScheduleID';
   PRINT N'';
   PRINT N'        EXEC msdb.dbo.sp_update_job'; 
   PRINT N'                   @job_id = @LS_BackupJobId';
   PRINT N'                   ,@enabled = ' + CAST(@enabled AS VARCHAR);
   PRINT N'';
   PRINT N'    END'; 
   PRINT N'';
   PRINT N'    ELSE BEGIN';
   PRINT N'        PRINT N''Issue adding job schedule for ' + quotename(@databaseName) + N', quitting batch execution...'';';
   PRINT N'        RETURN;';
   PRINT N'    END;';
   PRINT N'';
   PRINT N'    EXEC master.dbo.sp_add_log_shipping_primary_secondary';
   PRINT N'                @primary_database = N''' + @databaseName + N'''';
   PRINT N'               ,@secondary_server = N''' + @secondary_server + N''''; 
   PRINT N'               ,@secondary_database = N''' + @databaseName + N'''';
   PRINT N'               ,@overwrite = ' + CAST(@overwrite AS VARCHAR);
   PRINT N'';
   PRINT N'   PRINT N''Logshipping successfully configured.'';';
   PRINT N'   PRINT N'''';';
   PRINT N'';

   PRINT N'';
   PRINT N'END TRY';
   PRINT N'BEGIN CATCH';
   PRINT N'    PRINT N''There was an issue configuring logshipping on ' + quotename(@databaseName) + N'. Quitting batch execution and cleaning up artifacts'';';
   PRINT N'    PRINT N'''';';
   PRINT N'    DELETE FROM log_shipping_primary_databases WHERE primary_database = N''' + @databaseName + N''';';
   PRINT N'    DELETE FROM log_shipping_monitor_primary WHERE primary_database = N''' + @databaseName + N''';';
   PRINT N'    DELETE FROM log_shipping_primary_secondaries WHERE secondary_database = N''' + @databaseName + N''';';
   PRINT N'    EXEC sp_delete_job @job_id = @LS_BackupJobID';
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
PRINT N'SELECT TOP 1 @startTime = timestamps FROM #elapsedTime;';
PRINT N'';
PRINT N'PRINT N''Total Elapsed Time: '' +  STUFF(CONVERT(NVARCHAR(12), CURRENT_TIMESTAMP - @startTime, 14), 9, 1, ''.''); --hh:mi:ss.mmm';
PRINT N'';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''*****Primary Logshipping of databases on ' + quotename(@@SERVERNAME) + N' complete. Continue to Primary Monitor Logshipping*****'';';
PRINT N'';
PRINT N'DROP TABLE #elapsedTime';

--End of script, proceed to Primary Monitor Logshipping