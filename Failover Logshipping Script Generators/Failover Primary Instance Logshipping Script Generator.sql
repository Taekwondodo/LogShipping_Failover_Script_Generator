/*

Use this script to produce a T-SQL script to run on the secondary instances of a logshipping configuration to complete the failover

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
--Instead of using the registry to find the backup we'll use msdb.dbo.log_shipping_secondary_databases
--
--We keep the job ids to ensure they're disabled before configuring logshipping

declare @databases table (
   secondary_id     uniqueidentifier not null primary key
  ,database_name    nvarchar(128) not null 

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
--LEFT JOIN msdb.dbo.log_shipping_secondary AS lss  ON (lssd.secondary_id = lss.secondary_id)
--
--We don't want a db if it is offline, not yet restored, or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   AND d.is_read_only = 0 
   AND d.is_in_stanby = 0
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lssd.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   raiserror('There are no databases eligible to be configured for logshipping, 20, -1');

select
   @databaseFilter as DatabaseFilter
 , @backupFilePath as BackupFilePath
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
PRINT N'-- Use the following script to configure failover logshipping for the following databases on ' + quotename(@@servername) + ':';
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

   PRINT N'--' + @databaseName;

END;     

PRINT N'--';
PRINT N'-- Script generated @ ' + convert(nvarchar, current_timestamp, 120) + N' by ' + quotename(suser_sname()) + N'.';
PRINT N'--================================';
PRINT N'';
PRINT N'PRINT N''Beginning Logshipping Configurations...'
PRINT N'PRINT N'''';';

--
--End of setup, start logshipping 
--
DECLARE @backupPath           nvarchar(260)
       ,@monitorServer        nvarchar(128)
       ,@secondaryServer      nvarchar(128)
       ,@secondaryDatabase    nvarchar(128)

SET @databaseName = N'';

WHILE(EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName))BEGIN

   SELECT TOP 1
      @databaseName = d.database_name
     ,@backupPath = lss.backup_source_directory
     ,@monitorServer = lss.monitor_server
     ,@secondaryServer = lss.primary_server
     ,@secondaryDatabase = lss.primary_database
   FROM
      @databases AS d LEFT JOIN log_shipping_secondary AS lss ON (d.secondary_id = lss.secondary_id)
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

   DECLARE @LS_BackUpScheduleUID	As uniqueidentifier 
   DECLARE @LS_BackUpScheduleID	AS int 


   EXEC msdb.dbo.sp_add_schedule 
		   @schedule_name =N'LSBackupSchedule_sql-logship-s1' 
		   ,@enabled = 1 
		   ,@freq_type = 4 
		   ,@freq_interval = 1 
		   ,@freq_subday_type = 4 
		   ,@freq_subday_interval = 15 
		   ,@freq_recurrence_factor = 0 
		   ,@active_start_date = 20151002 --change to current date when script is rrun
		   ,@active_end_date = 99991231 
		   ,@active_start_time = 0 
		   ,@active_end_time = 235900 
		   ,@schedule_uid = @LS_BackUpScheduleUID OUTPUT 
		   ,@schedule_id = @LS_BackUpScheduleID OUTPUT 

   EXEC msdb.dbo.sp_attach_schedule 
		   @job_id = @LS_BackupJobId 
		   ,@schedule_id = @LS_BackUpScheduleID  

   EXEC msdb.dbo.sp_update_job 
		   @job_id = @LS_BackupJobId 
		   ,@enabled = 1 


   END 


   EXEC master.dbo.sp_add_log_shipping_primary_secondary 
		   @primary_database = N'Test' 
		   ,@secondary_server = N'sql-logship-p' 
		   ,@secondary_database = N'Test' 
		   ,@overwrite = 1 

END
-- ****** End: Script to be run at Primary: [sql-logship-s]  ******


