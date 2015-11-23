/*
Since our current tests to make sure the copy & restore jobs don't work because of the time it takes for the LS tables to update, we're going to have to find
an acutal solution.

We can't just wait for ls.secondary to update the last copied folder since if the job fails to copy the tail log it'll never update, and trying to find an average
time to wait before determining that the job's run was a 'failure' would be impractical and unreliable

So we're going to look towards LS.monitor_history_detail (MHD), since it reliably updates regardless of what the outcome of the job was (as long as the job starts).
In the testing here MHD takes much longer to update than LS.secondary (~20s vs ~8s), so we could just assume that LS.secondary gets updated before MHD in which 
case we could just use that as the indicator to check LS.secondary for the last copied file, however we don't know that for certain and trying to do so is probably
impractical as that most likely isn't documented anywhere.

So we're going to wait for MHD to have a row inserted and then wait for the final log row (success, error, etc.) to be inputted afterwards.

****TLDR: The entire purpose of checking MHD is to give an indicator of whether or not the current last copied file should be different than the initial****

At which point we're going to use a time_stamp that we set before the copy job was started in order to filter out all of the logs in MHD that we don't want.
We're then going to search through those messages for LIKE N'%Number of files copied:%, then we're (somehow) going to extract the number of files that were copied
from them. At that point if the number is > 0 THEN we're going to check LS.secondary for the last copied file and proceed with our normal checking of the file.
*/

use msdb

exec sp_start_job @job_name = 'LSBackup_LogshipTest_1'

go

:Connect sql-logship-s 

go

use msdb

DECLARE @initialCopy nvarchar(128)   -- initial last_copied file
DECLARE @currentCopy nvarchar(128)   -- used to check the current last_copied_file
DECLARE @start datetime              -- for getting the overlapsed time
Declare @stop datetime               -- for getting the overlapsed time
declare @beginTest datetime          -- used to filter out MHD
declare @beforeLogCount nvarchar(10) -- for the count(*) of MHD before the copy job is ran
declare @afterLogCount nvarchar(10)  -- for the count(8) of MHD after the copy job is run

WAITFOR DELAY '00:00:05'

--get the initial last copied file

SELECT
   @initialCopy = lss.last_copied_file
FROM
   log_shipping_secondary AS lss
WHERE
   lss.primary_database = 'LogshipTest_1'

print 'initial: ' + @initialCopy

-- get the initial count(*) for MHD

select 
   @beforeLogCount = Count(*)
from 
   log_shipping_monitor_history_detail

set @beginTest = current_timestamp

print 'before: ' + @beforeLogCount

-- start the copy job

exec sp_start_job @job_name = 'LSCopy_sql-logship-p_LogshipTest_1'

--start the timer

set @start = current_timestamp

-- get the current count(*) for MHD

select
   @afterLogCount = Count(*)
from
   log_shipping_monitor_history_detail

print 'right after: ' + @afterLogCount

-- wait for MHD to get updated

while(@afterLogCount = @beforeLogCount)BEGIN

   select
      @afterLogCount = Count(*)
   from
      log_shipping_monitor_history_detail

   print 'during: ' + @afterLogCount

END;

-- Wait for all of the rows to be inserted into MHD from the copy job's run

select top 1 @beforeLogCount = session_status from log_shipping_monitor_history_detail order by log_time desc

--We'll  need to change this to @beforeLogCount != 0 || 1 since a job can end on 2, 3 or 4 (success, error, warning)

while(@beforeLogCount != 2)BEGIN

print 'session: ' + @beforeLogCount

   waitfor delay '00:00:1'

   select top 1 @beforeLogCount = session_status from log_shipping_monitor_history_detail order by log_time desc

END;

--getting the final count(*) just to make sure the previous worked correctly

select
   @afterLogCount = Count(*)
from
   log_shipping_monitor_history_detail

print 'finished: ' + @afterLogCount

set @stop = current_timestamp

print datediff(ms, @start, @stop)


--The following (checking LS.secondary by itself) probably isn't going to be used for reasons discussed in the header

/*

--start timer

set @start = current_timestamp

--get current last_copied_file after copy job is run

SELECT
   @currentCopy = lss.last_copied_file
FROM
   log_shipping_secondary AS lss
WHERE
   lss.primary_database = 'LogshipTest_1'

--wait for the last copied file to change

while(@currentCopy = @initialCopy)BEGIN

print 'current: ' + @currentCopy

   WAITFOR DELAY '00:00:01'

   SELECT
   @currentCopy = lss.last_copied_file
      FROM
   log_shipping_secondary AS lss
      WHERE
   lss.primary_database = 'LogshipTest_1'


END;

print 'end: ' + @currentCopy

set @stop = current_timestamp

print datediff(ms, @start, @stop)
*/