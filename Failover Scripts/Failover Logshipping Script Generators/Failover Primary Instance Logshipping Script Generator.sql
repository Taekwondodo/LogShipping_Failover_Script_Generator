/*
This script is ran on the original primary instance after the secondary instance databases have been restored

Use this script to produce a T-SQL script to run on the original secondary instance you're failing over to to configure it as a primary instance for the server you're failing over from

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
declare @databases table (
   primary_id                    uniqueidentifier not null primary key --ID of the original database
  ,secondary_database            nvarchar(128) not null
  ,backup_directory              nvarchar(500) not null
  ,backup_job_id                 uniqueidentifier not null
);

insert into @databases (
   primary_id
  ,secondary_database
  ,backup_directory
  ,backup_job_id
)
select
   lspd.primary_id as primary_id, lsps.secondary_database as secondary_database, lspd.backup_directory as backup_directory, lspd.backup_job_id as backup_job_id 
from
   msdb.dbo.log_shipping_primary_databases AS lspd LEFT JOIN master.sys.databases AS d ON (lspd.primary_database = d.name)
   LEFT JOIN log_shipping_primary_secondaries AS lsps ON (lsps.primary_id = lspd.primary_id)
--
--We don't want to configure logshipping to a db if it is offline, not yet in standby/read-only, or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   AND d.is_read_only = 1 
   AND d.is_in_standby = 1
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lsps.secondary_database ASC;

IF NOT EXISTS(SELECT * FROM @databases)
   raiserror('There are no databases eligible to be configured for logshipping', 17, -1);

select
   @databaseFilter as DatabaseFilter
 , @exclude_system as ExcludeSystemDatabases;

if (@debug = 1) begin

   select
      *
   from
      @databases AS d
   order by
      d.secondary_database;

end;

DECLARE @jobInfo AS TABLE(
              job_id                      uniqueidentifier not null primary key
             ,target_database_id          uniqueidentifier not null
             ,backup_retention_period     int not null
             ,backup_threshold            int not null
             ,threshold_alert_enabled     bit not null
             ,history_retention_period    int not null
             ,freq_type                   int not null
             ,freq_interval               int not null
             ,freq_subday_type            int not null
             ,freq_subday_interval        int not null
             ,freq_recurrent_factor       int not null
)
INSERT INTO @jobInfo(
             job_id
            ,target_database_id
            ,backup_retention_period
            ,backup_threshold
            ,threshold_alert_enabled
            ,history_retention_period
            ,freq_type
            ,freq_interval
            ,freq_subday_type
            ,freq_subday_interval
            ,freq_recurrent_factor
)
SELECT 
   d.backup_job_id as job_id
  ,d.primary_id as target_database_id
  ,lspd.backup_retention_period as backup_retention_period
  ,lsmp.backup_threshold as backup_threshold
  ,lsmp.threshold_alert_enabled as threshold_alert_enabled
  ,lsmp.history_retention_period as history_retention_period
  ,ss.freq_type as freq_type
  ,ss.freq_interval as freq_interval
  ,ss.freq_subday_type as freq_subday_type
  ,ss.freq_subday_interval as freq_subday_interval
  ,ss.freq_recurrence_factor as freq_recurrent_factor
FROM
   @databases as d 
   LEFT JOIN log_shipping_primary_databases as lspd ON (lspd.primary_id = d.primary_id)
   LEFT JOIN log_shipping_monitor_primary as lsmp ON (lsmp.primary_id = d.primary_id)
   LEFT JOIN sysjobschedules as sjs ON (sjs.job_id = d.backup_job_id)
   LEFT JOIN sysschedules as ss ON (ss.schedule_id = sjs.schedule_id)
;

--================================

DECLARE @databaseName      nvarchar(128)
       ,@backupPath        nvarchar(500)
       ,@secondaryServer  nvarchar(128)
       ,@maxLen            int
       

SET @databaseName = N'';
SET @secondaryServer = (SELECT TOP 1 secondary_server FROM log_shipping_primary_secondaries);
SET @maxLen = (SELECT MAX(datalength(d.secondary_database)) FROM @databases as d);

PRINT N'/*';
PRINT N'*****RUN ON THE ORIGINAL SECONDARY*****';
PRINT N'';
PRINT N'Since the configuration can''t be contained within a transaction, if an error occurs during execution there is a possibility that artifacts may be created depending on when the error occurred';
PRINT N'Here is a list of all the tables that may contain artifacts (assume the tables are within msdb):'
PRINT N'';
PRINT N'log_shipping_primary_databases';
PRINT N'log_shipping_monitor_primary';
PRINT N'log_shipping_primary_secondaries';
PRINT N'';
PRINT N'There are several tables that contain artifacts from the creation of the backup jobs, however simply deleting the jobs will remove the artifacts';
PRINT N'';
PRINT N'A check is peformed during the script to make sure the database in online, has been restored, and isn''t already configured as a primary';
PRINT N'Use the following script to attempt to configure failover logshipping for the following databases as primaries on ' + quotename(@secondaryServer) + N' with backup destinations:';
PRINT N'*/';




WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.secondary_database > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.secondary_database
     ,@backupPath = d.backup_directory
   FROM
      @databases AS d 
   WHERE 
      d.secondary_database > @databaseName

   ORDER BY d.secondary_database ASC;

   PRINT N'--    ' + left(@databaseName + replicate(N' ', @maxLen / 2), @maxLen / 2) + N'   ' + @backupPath;

END;     

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
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
PRINT N'';

--
--End of setup, start logshipping 
--
DECLARE  @monitorServer          nvarchar(128)
        ,@originalPrimary        nvarchar(128)
        ,@backupRetention        nvarchar(10)
        ,@backupThreshold        nvarchar(10)
        ,@thresholdAlert         nvarchar(1)
        ,@historyRetention       nvarchar(10)
        ,@freqType               nvarchar(10)
        ,@freqInterval           nvarchar(10)
        ,@freqSubday             nvarchar(10)
        ,@freqSubdayInterval     nvarchar(10)
        ,@freqRecurrent          nvarchar(10)
                     
       
SET @databaseName = N'';




WHILE(EXISTS(SELECT * FROM @databases AS d WHERE @databaseName < d.secondary_database))BEGIN

   SELECT TOP 1
      @databaseName = d.secondary_database
     ,@backupPath = d.backup_directory
     ,@monitorServer = lspd.monitor_server
     ,@originalPrimary = lspd.primary_database
     ,@backupRetention = ji.backup_retention_period
     ,@backupThreshold = ji.backup_threshold
     ,@thresholdAlert = ji.threshold_alert_enabled
     ,@historyRetention = ji.history_retention_period
     ,@freqType = ji.freq_type
     ,@freqInterval = ji.freq_interval
     ,@freqSubday = ji.freq_subday_type
     ,@freqSubdayInterval = ji.freq_subday_interval
     ,@freqRecurrent = ji.freq_recurrent_factor
   FROM
      @databases AS d LEFT JOIN log_shipping_primary_databases AS lspd ON (d.primary_id = lspd.primary_id)
      LEFT JOIN @jobInfo as ji ON (ji.target_database_id = d.primary_id)
   WHERE 
      @databaseName < d.secondary_database
   ORDER BY
      d.secondary_database ASC;     
  
      
   PRINT N'GO';
   PRINT N'';
   PRINT N'BEGIN TRY';
   PRINT N'';  
   PRINT N'    PRINT N''=================================='';';
   PRINT N'    PRINT N''Beginning failover logshipping configuration on ' + quotename(@databaseName) + N''';';
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
   PRINT N'    --Check to make sure the database isn''t already configured as a primary, is online, and has been restored';
   PRINT N'';
   PRINT N'    IF(EXISTS(';
   PRINT N'        SELECT';
   PRINT N'           *';
   PRINT N'        FROM'; 
   PRINT N'           master.sys.databases AS d LEFT JOIN log_shipping_primary_databases AS lspd ON (d.name = lspd.primary_database)';
   PRINT N'        WHERE';
   PRINT N'           d.name = N''' + @databaseName + N'''';
   PRINT N'           AND lspd.primary_database IS NULL';
   PRINT N'           AND d.state_desc = ''ONLINE''';
   PRINT N'           AND d.is_in_standby = 0';
   PRINT N'           AND d.is_read_only = 0';
   PRINT N'    ))BEGIN';
   PRINT N'';
   PRINT N'         EXEC @SP_Add_RetCode = master.dbo.sp_add_log_shipping_primary_database'; 
   PRINT N'            @database = N''' + @databaseName + N''''; 
   PRINT N'           ,@backup_directory = N''' + @backupPath + N'''';
   PRINT N'           ,@backup_share = N''' + @backupPath + N''''; 
   PRINT N'           ,@backup_job_name = N''LSBackup_' + @databaseName + N''''; 
   PRINT N'           ,@backup_retention_period = ' + @backupRetention ;
   PRINT N'           ,@monitor_server = N''' + @monitorServer + N'''';
   PRINT N'           ,@monitor_server_security_mode = 1';
   PRINT N'           ,@backup_threshold = ' + @backupThreshold;
   PRINT N'           ,@threshold_alert_enabled = ' + @thresholdAlert;
   PRINT N'           ,@history_retention_period = ' + @historyRetention;
   PRINT N'           ,@backup_job_id = @LS_BackupJobId OUTPUT';
   PRINT N'           ,@primary_id = @LS_PrimaryId OUTPUT';
   PRINT N'           ,@overwrite = 1';
   PRINT N'           ,@ignoreremotemonitor = 1';
   PRINT N'';
   PRINT N'';
   PRINT N'         IF (@@ERROR = 0 AND @SP_Add_RetCode = 0)';
   PRINT N'         BEGIN';
   PRINT N'';
   PRINT N'             SET @LS_BackUpScheduleUID = NULL';
   PRINT N'             SET @LS_BackUpScheduleID = NULL'; 
   PRINT N'';
   PRINT N'';
   PRINT N'             EXEC msdb.dbo.sp_add_schedule';
   PRINT N'                        @schedule_name =N''LSBackupSchedule_' + lower(@secondaryServer) + N'1' + N''''; --The 1 is kept from the original configuration
   PRINT N'                        ,@enabled = 1';
   PRINT N'                        ,@freq_type = ' + @freqType;
   PRINT N'                        ,@freq_interval = ' + @freqInterval;
   PRINT N'                        ,@freq_subday_type = ' + @freqSubday;
   PRINT N'                        ,@freq_subday_interval = ' + @freqSubdayInterval;
   PRINT N'                        ,@freq_recurrence_factor = ' + @freqRecurrent;
   PRINT N'                        ,@active_start_date = @currentDate'; 
   PRINT N'                        ,@active_end_date = 99991231';
   PRINT N'                        ,@active_start_time = 0';
   PRINT N'                        ,@active_end_time = 235900';
   PRINT N'                        ,@schedule_uid = @LS_BackUpScheduleUID OUTPUT';
   PRINT N'                        ,@schedule_id = @LS_BackUpScheduleID OUTPUT';
   PRINT N'';
   PRINT N'             EXEC msdb.dbo.sp_attach_schedule';
   PRINT N'                        @job_id = @LS_BackupJobId';
   PRINT N'                        ,@schedule_id = @LS_BackUpScheduleID';
   PRINT N'';
   PRINT N'             EXEC msdb.dbo.sp_update_job'; 
   PRINT N'                        @job_id = @LS_BackupJobId';
   PRINT N'                        ,@enabled = 1';
   PRINT N'';
   PRINT N'         END'; 
   PRINT N'';
   PRINT N'         ELSE BEGIN';
   PRINT N'             PRINT N''Issue adding job schedule for ' + quotename(@databaseName) + N', quitting batch execution...'';';
   PRINT N'             RETURN;';
   PRINT N'         END;';
   PRINT N'';
   PRINT N'         EXEC master.dbo.sp_add_log_shipping_primary_secondary';
   PRINT N'                     @primary_database = N''' + @databaseName + N'''';
   PRINT N'                    ,@secondary_server = N''' + @@SERVERNAME + N''''; 
   PRINT N'                    ,@secondary_database = N''' + @originalPrimary + N'''';
   PRINT N'                    ,@overwrite = 1';
   PRINT N'';
   PRINT N' 	      PRINT N''Logshipping successfully configured'';';
   PRINT N'          PRINT N'''';';
   PRINT N'';
   PRINT N'    END';
   PRINT N'    ELSE BEGIN';
   PRINT N'       PRINT N''' + quotename(@databaseName) + N' is either offline, not yet restored, or is already configured as a primary. Skipping...'';';
   PRINT N'       PRINT N'''';';
   PRINT N'    END;';
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

   raiserror('',0,1) WITH NOWAIT; --flush print buffer
END;

PRINT N' --Print the elapsed time';
PRINT N'';
PRINT N'DECLARE @startTime DATETIME';
PRINT N'       ,@endTime   DATETIME';
PRINT N'';
PRINT N'INSERT INTO #elapsedTime SELECT CURRENT_TIMESTAMP;';
PRINT N'SELECT @startTime = MIN(timestamps), @endTime = MAX(timestamps) FROM #elapsedTime';
PRINT N'';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''Total Elapsed Time: '' +  STUFF(CONVERT(NVARCHAR(12), @endTime - @startTime, 14), 9, 1, ''.''); --hh:mi:ss.mmm';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''*****Failover primary logshipping complete. Continue to Failover Primary Monitor Logshipping script*****'';';
PRINT N'';
PRINT N'DROP TABLE #elapsedTime';

--End of script, continue to Failover Primary Monitor Logshipping script


