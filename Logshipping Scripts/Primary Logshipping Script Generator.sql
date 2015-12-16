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
set @exclude_system = 0;

--set @databaseFilter = N'Footprints';

--================================

exec xp_instance_regread
   @rootkey    = 'HKEY_LOCAL_MACHINE'
 , @key        = 'Software\Microsoft\MSSQLServer\MSSQLServer'
 , @value_name = 'BackupDirectory'
 , @value      = @backupFilePath output;

--if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\'; We're not appending to this

declare @databases table (
   database_name    nvarchar(128) not null primary key clustered
);

insert into @databases (
   database_name
  )

select 
   d.name as database_name
from 
   master.sys.databases as d
where
   (d.state_desc = N'ONLINE')
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
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

end;

/*
Configuring logshipping involves setting up a lot of variables.
To limit the amount of values you need to manually enter on the output script, you can setup defaults here that will be applied to all of the database logshipping configurations.
Then you can change the values for specific databases that require unique values in the output script.
The variables (that can) will initially be set to the default values as Microsoft sets them when they output a logshipping script
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

SET @secondary_server =  -- #INSERT
SET @backup_directory = @backupFilePath 
SET @backup_share = @backupFilePath 
SET @backup_job_name = N'LSBackup_' + @@SERVERNAME -- cannot be NULL, standard is 'LSBackup_@@servername'
SET @backup_retention_period = 4320    -- the length of time in minutes to retain the log backup file in the backup directory
SET @monitor_server =                  -- #INSERT         
SET @monitor_server_security_mode = 1  -- How the job is to connect to the monitor server. 1 is by the job's proxy account (Windows authetication) 
                                       --0 is a specific SQL Login
SET @backup_threshold = 60;          --The length of time, in minutes, after the last backup before a threshold_alert error is raised by the alert job
SET @threshold_alert_enabled = 1     --Whether or not a threshold_alert will be raised
SET @history_retention_period = 5760 --Length of time in minutes in which the history will be retained (Default is 4 days)
SET @overwrite = 1                   --Whether or not to overwrite a previous logship config for this instance
SET @ignoreremotemonitor = 1         --Whether or not to try and use the linked server to configure the monitor from the primary server (Hasn't worked)
    
SET @schedule_name = N'LSBackupSchedule_' + @@SERVERNAME + N'1'  -- Name does not have to be unique
SET @enabled = 1 --Whether or not jobs will run on this schedule

-- https://msdn.microsoft.com/en-us/library/ms187320.aspx --for the next 6
-- The default as it is here has the backup job running every 15 minutes
SET @freq_type = 4
SET @freq_interval = 1
SET @freq_subday_type = 4
SET @freq_subday_interval = 15
SET @freq_relative_interval = 0
SET @freq_recurrence_factor = 0

-- The following two are the dates in which the job will start and stop (permanently) running
SET @active_start_date = 0      -- A default is given if this value remains at 0
SET @active_end_date = 99991231 -- December 31st 9999

-- The following two are the times during the day in which the backup job will run
SET @active_start_time = 000000 -- 12:00:00 am
SET @active_end_time = 235959   -- 11:59:59 pm

--
-- End of Defaults setup
--


SET @databaseName = N'';
SET @maxLen = 

PRINT N'/*';
PRINT N'*****RUN ON ' + quotename(@@SERVERNAME) + N'*****';
PRINT N'Use the following script to attempt to configure failover logshipping for the following databases as primaries on ' + quotename(@@SERVERNAME) + N':';
PRINT N'*/';

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.secondary_database
     ,@backupPath = d.backup_directory
   FROM
      @databases AS d 
   WHERE 
      d.secondary_database > @databaseName

   ORDER BY d.secondary_database ASC;

   PRINT N'-- ' + quotename(@databaseName);

END;     

PRINT N'';
PRINT N'-- With the following configuration defaults:';
PRINT N'';
PRINT N'-- Secondary Server: ' + @secondary_server;
PRINT N'-- Monitor Server: ' +  @monitor_server;
PRINT N'-- Backup Directory: ' + @backup_directory;
PRINT N'-- Backup Share: ' + @backup_share;
PRINT N'-- Backup Retention Period: ' + CAST(@backup_retention_period AS VARCHAR);
PRINT N'-- Monitor Server Security Mode: ' + CAST(@monitor_server_security_mode AS VARCHAR);
PRINT N'-- Backup Threshold: ' + CAST(@backup_threshold AS VARCHAR);
PRINT N'-- Threshold Alert Enabled: ' + CAST(@threshold_alert_enabled AS VARCHAR);
PRINT N'-- History Retention Period ' + CAST(@history_retention_period AS VARCHAR);
PRINT N'-- Overwrite Pre-Existing Logshipping Configurations: ' + CAST(overwrite AS VARCHAR);
PRINT N'-- Manually Run Primary Monitor Script: ' + CAST(@ignoreremotemonitor AS VARCHAR);
PRINT N'';
PRINT N'-- And the following schedule defaults:';
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

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
