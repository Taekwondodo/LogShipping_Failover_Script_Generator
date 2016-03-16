/*

This script is ran on the server you want to setup as a primary for logshipping

Use this script to produce a T-SQL script to setup the server it is run on as a logshipping primary instance

*/

set nocount on;
go

use msdb;
go

declare @backupFilePath nvarchar(260)
      , @databaseFilter nvarchar(128)
      , @debug          bit
      , @exclude_system bit;

set @debug = 1;

--set @databaseFilter = N'Footprints';

--================================

-- Commenting the default backup directory code since the actual setup will involve a single directory on the network, not each instance's individual backup location

/*
exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'BackupDirectory'
 , @value      = @backupFilePath output;
*/

set @backupFilePath = N'\\pbrc.edu\files\share\MIS\DBA\Log Shipping Lab\Backups';

if (@backupFilePath not like N'\\%') set @backupFilePath = N'\\' + @@SERVERNAME + N'\' + REPLACE(@backupFilePath, N':', N'$'); 


use msdb

declare @databases table (
   database_name    nvarchar(128) not null primary key clustered
);

insert into @databases (
   database_name
  )
select 
   d.name as database_name
from 
   master.sys.databases as d left join log_shipping_primary_databases as lspd on (d.name = lspd.primary_database)
where
   --Check to make sure the database isn''t already configured as a primary, is online, restored, and isn't a system db
   lspd.primary_database is null 
   and d.name not in (N'master', N'model', N'msdb', N'tempdb')
   and d.state_desc = N'ONLINE'
   and d.is_in_standby = 0
   and d.is_read_only = 0
order by
   d.name asc;


if not exists(select * from @databases)
   raiserror('There are no databases eligible to be configured for logshipping', 17, -1);

if (@debug = 1) begin

   select
      *
   from
      @databases AS d
   order by
      d.database_name;

   select @backupFilePath as backup_file_path;
      
end;

/*
Configuring logshipping involves setting up a number of variables.
To limit the amount of values you need to manually enter on the output script, you can setup defaults here that will be applied to all of the database logshipping configurations.
Then you can change the values for specific databases that require unique values in the output script.
The variables (that can) will initially be set to the default values as Microsoft sets them when they generate a logshipping script
The rest will require input on your part and will be tagged with a #INSERT
*/

DECLARE  @secondary_server             SYSNAME, 
         @secondary_database           SYSNAME, 
         @backup_directory             NVARCHAR(500), 
         @backup_share                 NVARCHAR(500), 
         @backup_job_name              SYSNAME, 
         @backup_retention_period      INT, 
         @monitor_server               SYSNAME,
         @monitor_server_security_mode BIT, 
         @backup_threshold             INT, 
         @threshold_alert_enabled      BIT, 
         @history_retention_period     INT, 
         @overwrite                    BIT, 
         @ignoreremotemonitor          BIT, 
         @schedule_name                SYSNAME, 
         @enabled                      TINYINT, 
         @freq_type                    INT,
         @freq_interval                INT,
         @freq_subday_type             INT,
         @freq_subday_interval         INT,
         @freq_relative_interval       INT,
         @freq_recurrence_factor       INT,
         @active_start_date            INT, 
         @active_end_date              INT, 
         @active_start_time            INT, 
         @active_end_time              INT 

--
-- Set Defaults 
--

SET @secondary_server = N'sql-logship-s';               -- #INSERT #REMOVE
SET @backup_directory = @backupFilePath; 
SET @backup_share = @backupFilePath; 
SET @backup_job_name = N'LSBackup_';    -- Default is LSBackup_databaseName. The full string is defined within the script. This variable functions as a prefix to the database name
SET @backup_retention_period = 4320;    -- the length of time in minutes to retain the log backup file in the backup directory
SET @monitor_server = N'P003666-DT' ;                 -- #INSERT #REMOVE
SET @monitor_server_security_mode = 1;  -- How the job is to connect to the monitor server. 1 is by the job's proxy account (Windows authetication) 
                                        --0 is a specific SQL Login

SET @backup_threshold = 60;           --The length of time, in minutes, after the last backup before a threshold_alert error is raised by the alert job
SET @threshold_alert_enabled = 1;     --Whether or not a threshold_alert will be raised
SET @history_retention_period = 5760; --Length of time in minutes in which the history will be retained (Default is 4 days)
SET @overwrite = 1;                   --Whether or not to overwrite a previous logship config for this instance, 1 = True
SET @ignoreremotemonitor = 1;         --Whether or not to try and use the linked server to configure the monitor from the primary server (Hasn't worked in testing), 1 = ignore (Manually run script on monitor server)
    
SET @schedule_name = N'LSBackupSchedule_' + @@SERVERNAME + N'1'  -- Name does not have to be unique
SET @enabled = 1 --Whether or not jobs will run on this schedule, 1 = Run

-- https://msdn.microsoft.com/en-us/library/ms187320.aspx --for the next 6
-- The default as it is here has the backup job running every 15 minutes 24 hours a day
SET @freq_type = 4;
SET @freq_interval = 1;
SET @freq_subday_type = 4;
SET @freq_subday_interval = 15;
SET @freq_relative_interval = 0;
SET @freq_recurrence_factor = 0;

-- The following two are the dates in which the job will start and stop (permanently) running
SET @active_start_date = 0;    -- A default is given (timestamp when the script is run) if this value remains at 0
SET @active_end_date = 99991231; -- December 31st 9999

-- The following two make up the timespan during the day in which the backup job will run
SET @active_start_time = 000000; -- 12:00:00 am
SET @active_end_time = 235959;   -- 11:59:59 pm

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
PRINT N'Overwrite Pre-Existing Logshipping Configurations: ' + CAST(@overwrite AS VARCHAR) + N', 0 = Don''t Overwrite, 1 = Overwrite';
PRINT N'Manually Run Primary Monitor Script: ' + CAST(@ignoreremotemonitor AS VARCHAR);
PRINT N'';
PRINT N'And the following job schedule defaults. Link for reference: (https://msdn.microsoft.com/en-us/library/ms187320.aspx):';
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
   PRINT N'    PRINT N''Beginning primary logshipping configuration for ' + quotename(@databaseName) + N''';';
   PRINT N'';
   PRINT N'    DECLARE @LS_BackupJobId           AS uniqueidentifier'; 
   PRINT N'           ,@LS_PrimaryId           AS uniqueidentifier'; 
   PRINT N'           ,@SP_Add_RetCode           As int';
   PRINT N'           ,@LS_BackUpScheduleUID  AS uniqueidentifier';
   PRINT N'           ,@LS_BackUpScheduleID   AS int';
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
   PRINT N''
   PRINT N'';
   PRINT N'   PRINT N''Logshipping successfully configured.'';';
   PRINT N'   PRINT N'''';';
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
   PRINT N'GO';
   PRINT N'';
   PRINT N'-- Create full database backup for secondary instance databases to restore from';
   PRINT N'';
   PRINT N'PRINT N''Creating full database backup for ' + quotename(@databaseName) + N''';';
   PRINT N'PRINT N'''';';
   PRINT N'';
   PRINT N'BACKUP DATABASE ' + @databaseName
   PRINT N'TO DISK = N''' + @backup_directory + N'\' + @databaseName + N'_InitLSBackup.bak''';
   PRINT N'WITH FORMAT,';
   PRINT N'      MEDIANAME = N''' + @databaseName + N'_InitLSBackup'',';
   PRINT N'      NAME = N''' + @databaseName + N' Initial LS Backup'';';
   PRINT N'';
   PRINT N'PRINT N'''';';

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

select * from msdb.dbo.log_shipping_primary_databases;