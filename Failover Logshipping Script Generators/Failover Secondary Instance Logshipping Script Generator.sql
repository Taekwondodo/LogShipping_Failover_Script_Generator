/*

Use this script to produce a T-SQL script to run on the primary instance you're failing over 
from to configure it as a secondary instance for the server you're failing over to

*/

--We won't be able to fully run this script until the secondary instance is set up as a primary instance

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
  database_name            nvarchar(128) not null 
 ,backup_source_path       nvarchar(500) not null
 ,backup_destination_path  nvarchar(500) not null
);
insert into @databases (
   database_name
  ,backup_source_path
  ,backup_destination_path
)
select
   lsps.secondary_database AS database_name, lss.backup_source_directory AS backup_source_path, lss.backup_destination_directory AS backup_destination_path
from
    msdb.dbo.log_shipping_primary_secondaries AS lsps LEFT JOIN msdb.dbo.log_shipping_secondary AS lss ON (lsps.secondary_database = lss.primary_database)

--The join we usually do to sys.databases here to check if the db is online and such will have to be done within the outputted script since this is being ran
--on the primary instance where there isn't access to the state of the secondary instance's databases

where
    ((@databaseFilter is null) 
      or (lsps.secondary_database like N'%' + @databaseFilter + N'%'))
                                                  
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

DECLARE @jobInfo AS TABLE(
        @
)

DECLARE @databaseName               nvarchar(128)
       ,@backupSourcePath           nvarchar(500)
       ,@backupDestinationPath      nvarchar(500)
       ,@secondaryServer            nvarchar(128) --Since this script is ran on the primary, we can't use @@SERVERNAME to get the name of the secondary 
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

DECLARE @primaryDatabase            nvarchar(128)
   
SET @databaseName = N'';

WHILE(EXISTS(SELECT * FROM @databases as d. WHERE @databaseName > d.database_name ORDER BY d.database_name ASC))BEGIN

   SELECT TOP 1
       @databaseName = d.database_name
      ,@backupSourcePath = d.backup_source_path
      ,@backupDestinationPath = d.backup_destination_path
      ,@primaryDatabase = lspd.primary_database
   FROM
      @databases AS d LEFT JOIN msdb.dbo.log_shipping_primary_databases AS lspd ON (d.database_name = lspd.primary_database)
   WHERE 
      @databaseName > d.database_name
   ORDER BY
      d.database_name ASC;


   PRINT N'DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier';
   PRINT N'DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier'; 
   PRINT N'DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier'; 
   PRINT N'DECLARE @LS_Add_RetCode	               As int'; 
   PRINT N'DECLARE @currentDate                   AS nvarchar(8)';
   PRINT N'';
   PRINT N'SET @currentDate = convert(nvarchar(8), CURRENT_TIMESTAMP, 112); --YYYYMMHH';
   PRINT N'';
   PRINT N'EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary'; 
   PRINT N'         @primary_server = N''' + @@SERVERNAME + N'''';  
   PRINT N'        ,@primary_database = N''' + @primaryDatabase + N'''';
   PRINT N'        ,@backup_source_directory = N''' + @backupSourcePath + N'''';
   PRINT N'        ,@backup_destination_directory = N''' + @backupDestinationPath + N''''; 
   PRINT N'        ,@copy_job_name = N''LSCopy_' + @secondaryServer + N'_' + @database + N''''; 
   PRINT N'        ,@restore_job_name = N''LSRestore_' + @secondaryServer + N'_' + @database + N''''; 
   PRINT N'        ,@file_retention_period = 4320';
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
   PRINT N'         ,@freq_type = 4'; 
   PRINT N'	 	,@freq_interval = 1'; 
   PRINT N'	 	,@freq_subday_type = 4'; 
   PRINT N'	 	,@freq_subday_interval = 15'; 
   PRINT N'	 	,@freq_recurrence_factor = 0 ';
   PRINT N'	 	,@active_start_date =' + @currentDate;
   PRINT N'	 	,@active_end_date = 99991231'; 
   PRINT N'	 	,@active_start_time = 0'; 
   PRINT N'	 	,@active_end_time = 235900'; 
   PRINT N'	 	,@schedule_uid = @LS_SecondaryCopyJobScheduleUID OUTPUT'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryCopyJobScheduleID OUTPUT'; 
   PRINT N'';
   PRINT N'EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'	      @job_id = @LS_Secondary__CopyJobId ';
   PRINT N'	 	,@schedule_id = @LS_SecondaryCopyJobScheduleID '; 

   PRINT N'DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier'; 
   PRINT N'DECLARE @LS_SecondaryRestoreJobScheduleID	AS int'; 


   PRINT N'EXEC msdb.dbo.sp_add_schedule'; 
   PRINT N'		 @schedule_name =N''DefaultRestoreJobSchedule'; 
   PRINT N'	 	,@enabled = 1 ';
   PRINT N'	 	,@freq_type = 4 ';
   PRINT N'	 	,@freq_interval = 1 ';
   PRINT N'	 	,@freq_subday_type = 4 ';
   PRINT N'	 	,@freq_subday_interval = 15 ';
   PRINT N'	 	,@freq_recurrence_factor = 0 ';
   PRINT N'	 	,@active_start_date = ' + @currentDate;
   PRINT N'	 	,@active_end_date = 99991231 ';
   PRINT N'	 	,@active_start_time = 0 ';
   PRINT N'	 	,@active_end_time = 235900 ';
   PRINT N'	 	,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT ';

   PRINT N'EXEC msdb.dbo.sp_attach_schedule ';
   PRINT N'		 @job_id = @LS_Secondary__RestoreJobId'; 
   PRINT N'	 	,@schedule_id = @LS_SecondaryRestoreJobScheduleID '; 
   P

   PRINT N'END 


   PRINT N'DECLARE @LS_Add_RetCode2	As int 


   PRINT N'IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
   PRINT N'BEGIN 

   PRINT N'EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database 
		   @secondary_database = N'Test' 
   PRINT N'	 	,@primary_server = N'sql-logship-s' 
   PRINT N'	 	,@primary_database = N'Test' 
   PRINT N'	 	,@restore_delay = 0 
   PRINT N'	 	,@restore_mode = 1 
   PRINT N'	 	,@disconnect_users	= 0 
   PRINT N'	 	,@restore_threshold = 45   
   PRINT N'	 	,@threshold_alert_enabled = 1 
   PRINT N'	 	,@history_retention_period	= 5760 
   PRINT N'	 	,@overwrite = 1 
   PRINT N'	 	,@ignoreremotemonitor = 1 


   PRINT N'END 


   PRINT N'IF (@@error = 0 AND @LS_Add_RetCode = 0) 
   PRINT N'BEGIN 

   PRINT N'EXEC msdb.dbo.sp_update_job 
		   @job_id = @LS_Secondary__CopyJobId 
   PRINT N'	 	,@enabled = 1 

   PRINT N'EXEC msdb.dbo.sp_update_job 
		   @job_id = @LS_Secondary__RestoreJobId 
   PRINT N'	 	,@enabled = 1 