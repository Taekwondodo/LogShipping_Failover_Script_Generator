/*

Use this script to produce a T-SQL script to run on the primary instance you're failing over 
from to configure it as a secondary instance for the server you're failover over to

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
  ,database_name    nvarchar(128) not null 

);
insert into @databases (
   database_name
)
select
   lsps.secondary_database AS database_name
from
    msdb.dbo.log_shipping_primary_secondaries AS lsps 

--The join we usually do to sys.databases here to check if the db is online and such will have to be done within the outputted script since this is being ran
--on the primary instance where there isn't access to the state of the secondary instance's databases

where
    ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lsps.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   raiserror('There are no secondary databases eligible to be configured for logshipping', 20, -1);

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
PRINT N'-- Use the following script to configure failover logshipping for the following databases as secondaries on ' + quotename(@@servername) + ':';
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

--
--End of setup, start logshipping 
--

DECLARE @databaseName               nvarchar(128)
       ,@primaryDatabase            nvarchar(128)
       ,@backupSourcePath           nvarchar(260)
       ,@backupDestinationPath      nvarchar(260)
       ,@currentDate                nvarchar(8) --Needs to be YYYYMMHH format 

SET @databaseName = N'';
SET @currentDate = convert(nvarchar(8), CURRENT_TIMESTAMP, 112); --YYYYMMHH

WHILE(EXISTS(SELECT * FROM 

DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier 
DECLARE @LS_Add_RetCode	As int 


EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary 
		@primary_server = N'sql-logship-s' 
		,@primary_database = N'Test' 
		,@backup_source_directory = N'\\pbrc.edu\files\share\MIS\DBA\Log Shipping Lab\Backups' 
		,@backup_destination_directory = N'\\pbrc.edu\files\share\MIS\DBA\Log Shipping Lab\Backups\Secondary (Copy Job)' 
		,@copy_job_name = N'LSCopy_sql-logship-s_Test' 
		,@restore_job_name = N'LSRestore_sql-logship-s_Test' 
		,@file_retention_period = 4320 
		,@monitor_server = N'P003666-DT' 
		,@monitor_server_security_mode = 1 
		,@overwrite = 1 
		,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT 
		,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT 
		,@secondary_id = @LS_Secondary__SecondaryId OUTPUT 

IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

DECLARE @LS_SecondaryCopyJobScheduleUID	As uniqueidentifier 
DECLARE @LS_SecondaryCopyJobScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'DefaultCopyJobSchedule' 
		,@enabled = 1 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = 15 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20151002 
		,@active_end_date = 99991231 
		,@active_start_time = 0 
		,@active_end_time = 235900 
		,@schedule_uid = @LS_SecondaryCopyJobScheduleUID OUTPUT 
		,@schedule_id = @LS_SecondaryCopyJobScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_Secondary__CopyJobId 
		,@schedule_id = @LS_SecondaryCopyJobScheduleID  

DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier 
DECLARE @LS_SecondaryRestoreJobScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'DefaultRestoreJobSchedule' 
		,@enabled = 1 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = 15 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20151002 
		,@active_end_date = 99991231 
		,@active_start_time = 0 
		,@active_end_time = 235900 
		,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT 
		,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_Secondary__RestoreJobId 
		,@schedule_id = @LS_SecondaryRestoreJobScheduleID  


END 


DECLARE @LS_Add_RetCode2	As int 


IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database 
		@secondary_database = N'Test' 
		,@primary_server = N'sql-logship-s' 
		,@primary_database = N'Test' 
		,@restore_delay = 0 
		,@restore_mode = 1 
		,@disconnect_users	= 0 
		,@restore_threshold = 45   
		,@threshold_alert_enabled = 1 
		,@history_retention_period	= 5760 
		,@overwrite = 1 
		,@ignoreremotemonitor = 1 


END 


IF (@@error = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_Secondary__CopyJobId 
		,@enabled = 1 

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_Secondary__RestoreJobId 
		,@enabled = 1 

END 