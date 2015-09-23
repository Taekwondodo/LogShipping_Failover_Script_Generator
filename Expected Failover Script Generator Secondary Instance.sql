/*

Use this script to produce a T-SQL script to failover all of the online logshipped databases on current server, matching filters, to the backup location specified 
during their logshipping configurations

*/

set nocount on;
go

use master;
go

declare @backupFilePath nvarchar(260)
      , @databaseFilter nvarchar(128)
      , @debug          bit
      , @exclude_system bit;

set @debug = 1;
set @exclude_system = 1; --So system tables are excluded

--set @databaseFilter = N'Footprints';

--================================
--
--Instead of using the registry to find the backup we'll use msdb.dbo.log_shipping_primary_databases, which also functions as the check
--to make sure the db is logshipped
--
/*
SELECT top 1
   @backupFilePath = backup_directory
FROM msdb.dbo.log_shipping_primary_databases
;


if (@backupFilePath not like N'%\') set @backupFilePath = @backupFilePath + N'\';
*/

--secondary_id necessary to pair databases to their jobs

declare @databases table (
   secondary_id     uniqueidentifier not null primary key
  ,database_name    nvarchar(128) not null 
  ,copy_job_id      uniqueidentifier not null
  ,restore_job_id   uniqueidentifier not null
);
insert into @databases (
   database_name
  ,secondary_id
  ,copy_job_id
  ,restore_job_id
)
select
   lssd.secondary_database as database_name, lssd.secondary_id as secondary_id, lss.copy_job_id, lss.restore_job_id
from
   msdb.dbo.log_shipping_secondary_databases AS lssd 
   LEFT JOIN sys.databases AS d ON (lssd.secondary_database = d.name)
   LEFT JOIN msdb.dbo.log_shipping_secondary AS lss  ON (lssd.secondary_id = lss.secondary_id)
--
--We don't want a db if it is offline or if it matches our filter
--
where
   (d.state_desc = N'ONLINE')
   and ((@databaseFilter is null) 
      or (d.name like N'%' + @databaseFilter + N'%'))
                                                  
order by
   lssd.secondary_database;

IF NOT EXISTS(SELECT * FROM @databases)
   PRINT N'There are no selected databases configured for logshipping as a secondary database';

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

--Table that contains job information

DECLARE @jobs TABLE (
   job_id            uniqueidentifier NOT NULL PRIMARY KEY
  ,job_name          nvarchar(128) NOT NULL
  ,avg_runtime       int NOT NULL --HHMMSS format
  ,target_database   nvarchar(128) NOT NULL
);

INSERT INTO @jobs (
  job_id
 ,job_name
 ,avg_runtime
 ,target_database
)
SELECT 
       sj.job_id AS job_id, MAX(sj.name), AVG(t2.Total_Seconds) AS avg_runtime, MAX(lssd.secondary_database) AS target_database
FROM
    msdb.dbo.log_shipping_secondary_databases AS lssd 
    LEFT JOIN sys.databases AS d ON (lssd.secondary_database = d.name)
    LEFT JOIN msdb.dbo.log_shipping_secondary AS lss  ON (lssd.secondary_id = lss.secondary_id)
    RIGHT JOIN msdb.dbo.sysjobs AS sj ON (lss.copy_job_id = sj.job_id OR lss.restore_job_id = sj.job_id) 
    RIGHT JOIN msdb.dbo.sysjobhistory AS sjh ON (sjh.job_id = sj.job_id)
    OUTER APPLY (
         SELECT 
            RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 2) AS Seconds
           ,SUBSTRING(RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 4), 1, 2) AS Minutes
           ,SUBSTRING(RIGHT('000000' + CAST(sjh.run_duration AS varchar(12)), 6), 1, 2) AS Hours
    ) as t1
    OUTER APPLY (
          SELECT 
             CAST(t1.Hours AS INT) * 3600 + CAST(t1.Minutes AS INT) * 60 + CAST(t1.Seconds AS INT) AS Total_Seconds
    )as t2

WHERE sjh.step_id = 0 
      AND sj.enabled = 1
      AND (d.state_desc = N'ONLINE')
      AND ((@databaseFilter is null) OR (d.name like N'%' + @databaseFilter + N'%'))
      AND lssd.secondary_database IS NOT NULL

GROUP BY sj.job_id;


IF (@debug = 1) BEGIN

   SELECT * FROM @jobs AS ji 

END;


--================================

PRINT N'--================================';
PRINT N'--';
PRINT N'-- Use the following script to set up logshipping and disable secondary instance jobs on ' + quotename(@@servername) + ':';
PRINT N'--';

DECLARE @databaseName     nvarchar(128)
       ,@copyJobName      nvarchar(128)
       ,@restoreJobName   nvarchar(128)
       ,@maxlenDB         int
       ,@maxlenJob        int

SET @databaseName = N'';
SET @maxlenDB = (select max(datalength(j.target_database)) from @jobs as j);
SET @maxlenJob = (select max(datalength(j.job_name)) from @jobs as j);

WHILE EXISTS(SELECT * FROM @databases AS d WHERE d.database_name > @databaseName) BEGIN

   SELECT TOP 1
      @databaseName = d.database_name 
     ,@copyJobName = j.job_name 
     ,@restoreJobName = j2.job_name 
   FROM
      @databases AS d LEFT JOIN @jobs AS j ON (d.copy_job_id = j.job_id)
      LEFT JOIN @jobs as j2 ON(d.restore_job_id = j2.job_id)

   WHERE 
      d.database_name > @databaseName

   ORDER BY d.database_name ASC;

   PRINT LEFT(@databaseName + REPLICATE(N' ', @maxlenDB / 2), @maxlenDB / 2) + N'    ' + LEFT(@copyJobName + REPLICATE(N' ', @maxlenJob / 2), @maxlenJob / 2) + N'    ' + @restoreJobName ;

END;     

