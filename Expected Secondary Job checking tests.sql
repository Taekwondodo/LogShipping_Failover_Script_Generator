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

   waitfor delay '00:00:1';

END;

declare @session varchar
       ,@numCopied nvarchar(128)
       ,@message nvarchar(4000)

-- Wait for all of the rows to be inserted into MHD from the copy job's run

select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc

--We'll  need to change this to @beforeLogCount != 0 || 1 since a job can end on 2, 3 or 4 (success, error, warning)

while(@session = 0 or @session = 1)BEGIN

print 'session: ' + @session

   waitfor delay '00:00:1'

   select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc

END;

--getting the final count(*) just to make sure the previous worked correctly

select
   @afterLogCount = Count(*)
from
   log_shipping_monitor_history_detail

print 'finished: ' + @afterLogCount

set @stop = current_timestamp

print datediff(ms, @start, @stop)

--Determine if the copy job copied over anything

if(@session = 2)begin

   select top 1 
      @message = rtrim(l.message)
   from 
      log_shipping_monitor_history_detail as l
   order by log_time desc

   -- We're starting at the right side of the message taking one char at a time (incase the # of files copied is greater than 1 digit) and checking the ascii value until we don't get a number

   declare @index int
          ,@temp char;

   set @index = datalength(@message) / 2;
   set @temp = substring(@message, @index, 1)
   set @numCopied = '';

   while(ascii(@temp) > 47 and ascii(@temp) < 58)begin
      
      set @numCopied = @temp + @numCopied --append the new number to @numCopied
      set @index = @index - 1;
      set @temp = substring(@message, @index, 1)

   end;

   print N'Number of files copied: ' + @numCopied;

end
else begin
   print N'Job failed';
end;

-- If the number of files copied is nonzero, check LS.secondary for the backup and check to ensure it is the tail like we have been doing
-- Remembering to check the initial @lastCopiedFile to LS.last_copied_file, knowing now that a new one should be in the table eventually


-- Start the check for the restore job


declare @initialRestore nvarchar(500);

SELECT
   @initialRestore = lssd.last_restored_file
FROM
   log_shipping_secondary_databases AS lssd
WHERE
   lssd.secondary_database = 'LogshipTest_1'

print 'initial: ' + @initialRestore

-- get the initial count(*) for MHD

select 
   @beforeLogCount = Count(*)
from 
   log_shipping_monitor_history_detail

set @beginTest = current_timestamp

print 'before: ' + @beforeLogCount

-- start the restore job

exec sp_start_job @job_name = 'LSRestore_sql-logship-p_LogshipTest_1'

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

   waitfor delay '00:00:1';

END;

-- Wait for all of the rows to be inserted into MHD from the copy job's run

select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc

--We'll  need to change this to @beforeLogCount != 0 || 1 since a job can end on 2, 3 or 4 (success, error, warning)

while(@session = 0 or @session = 1)BEGIN

print 'session: ' + @session

   waitfor delay '00:00:1'

   select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc

END;

--getting the final count(*) just to make sure the previous worked correctly

select
   @afterLogCount = Count(*)
from
   log_shipping_monitor_history_detail

print 'finished: ' + @afterLogCount

set @stop = current_timestamp

print datediff(s, @start, @stop)

--Determine if the restore job restored anything

declare @numRestored nvarchar(10)

if(@session = 2)begin

   -- The # of logs restored isn't as simple to access as it was for the copy jobs, as it is one of the potentially numerous 1 session_status rows
   -- So we're grabbing all of the rows inserted after our timestamp (which will only be rows for the restore job we ran) and finding the one that has our information

   select  
      @message = rtrim(l.message)
   from 
      log_shipping_monitor_history_detail as l
   where
      log_time > @start
      and message like '%Number of log backup files restored:%'

   -- We're starting at the right side of the message taking one char at a time (incase the # of files copied is greater than 1 digit) and checking the ascii value until we don't get a number

   set @index = datalength(@message) / 2;
   set @temp = substring(@message, @index, 1)
   set @numRestored = '';

   while(ascii(@temp) > 47 and ascii(@temp) < 58)begin
      
      set @numRestored = @temp + @numRestored --append the new number to @numCopied
      set @index = @index - 1;
      set @temp = substring(@message, @index, 1)

   end;

   print N'Number of files restored: ' + @numRestored;

end
else begin
   print N'Job failed';
end;

-- If the number of restored logs is nonzero we check backupset to ensure the log was the tail backup
-- We start by ensuring the table is fully up to date by checking how many rows have been inserted since we started our timer
-- From testing it looks like backupset is up to date at this point, but we'll keep the check in anyway

while((select count(*) from backupset as b where b.backup_start_date > @start) > cast(@numRestored as int))begin
   
   print 'Waiting for backupset...';
   waitfor delay '00:00:01'

end;

-- At this point we check the top 1 from backupset as we have been doing for the log tail



-- This part won't be in the actual script, but for testing purposes we'll make sure the top 1 in backupset = last_restored_file


declare @lastRestored nvarchar(500)

select @lastRestored = last_restored_file from log_shipping_secondary_databases where secondary_database = 'LogShipTest_1';


RESTORE HEADERONLY from disk = @lastRestored;



--****************Translated Code********************






   PRINT N'	DECLARE @lastCopiedFile nvarchar(128)   -- initial last_copied file';
   PRINT N'	DECLARE @currentCopy nvarchar(128)   -- used to check the current last_copied_file';
   PRINT N'	DECLARE @start datetime              -- for getting the overlapsed time';
   PRINT N'	Declare @stop datetime               -- for getting the overlapsed time';
   PRINT N'	declare @beginTest datetime          -- used to filter out MHD';
   PRINT N'	declare @beforeLogCount nvarchar(10) -- for the count(*) of MHD before the copy job is ran';
   PRINT N'	declare @afterLogCount nvarchar(10)  -- for the count(8) of MHD after the copy job is run';
   PRINT N'';
   PRINT N'	WAITFOR DELAY '00:00:05'';
   PRINT N'';
   PRINT N'	--get the initial last copied file';
   PRINT N'';
   PRINT N'	SELECT';
   PRINT N'	   @lastCopiedFile = lss.last_copied_file';
   PRINT N'	FROM';
   PRINT N'	   log_shipping_secondary AS lss';
   PRINT N'	WHERE';
   PRINT N'	   lss.primary_database = 'LogshipTest_1'';
   PRINT N'';
   PRINT N'	print 'initial: ' + @lastCopiedFile';
   PRINT N'';
   PRINT N'	-- get the initial count(*) for MHD';
   PRINT N'';
   PRINT N'	select ';
   PRINT N'	   @beforeLogCount = Count(*)';
   PRINT N'	from ';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	set @beginTest = current_timestamp';
   PRINT N'';
   PRINT N'	print 'before: ' + @beforeLogCount';
   PRINT N'';


   PRINT N'	-- start the copy job';
   PRINT N'';
   PRINT N'	exec sp_start_job @job_name = 'LSCopy_sql-logship-p_LogshipTest_1'';
   PRINT N'';
   PRINT N'	--start the timer';
   PRINT N'';
   PRINT N'	set @start = current_timestamp';
   PRINT N'';
   PRINT N'	-- get the current count(*) for MHD';
   PRINT N'';
   PRINT N'	select';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	from';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	print 'right after: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	-- wait for MHD to get updated';
   PRINT N'';
   PRINT N'	while(@afterLogCount = @beforeLogCount)BEGIN';
   PRINT N'';
   PRINT N'	   select';
   PRINT N'	      @afterLogCount = Count(*)';
   PRINT N'	   from';
   PRINT N'	      log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	   print 'during: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	   waitfor delay '00:00:1';';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	declare @session varchar';
   PRINT N'	       ,@numCopied nvarchar(128)';
   PRINT N'	       ,@message nvarchar(4000)';
   PRINT N'';
   PRINT N'	-- Wait for all of the rows to be inserted into MHD from the copy job's run';
   PRINT N'';
   PRINT N'	select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc';
   PRINT N'';
   PRINT N'	--We'll  need to change this to @beforeLogCount != 0 || 1 since a job can end on 2, 3 or 4 (success, error, warning)';
   PRINT N'';
   PRINT N'	while(@session = 0 or @session = 1)BEGIN';
   PRINT N'';
   PRINT N'	print 'session: ' + @session';
   PRINT N'';
   PRINT N'	   waitfor delay '00:00:1'';
   PRINT N'';
   PRINT N'	   select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	--getting the final count(*) just to make sure the previous worked correctly';
   PRINT N'';
   PRINT N'	select';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	from';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	print 'finished: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	set @stop = current_timestamp';
   PRINT N'';
   PRINT N'	print datediff(ms, @start, @stop)';
   PRINT N'';
   PRINT N'	--Determine if the copy job copied over anything';
   PRINT N'';
   PRINT N'	if(@session = 2)begin';
   PRINT N'';
   PRINT N'	   select top 1 ';
   PRINT N'	      @message = rtrim(l.message)';
   PRINT N'	   from ';
   PRINT N'	      log_shipping_monitor_history_detail as l';
   PRINT N'	   order by log_time desc';
   PRINT N'';
   PRINT N'	   -- We're starting at the right side of the message taking one char at a time (incase the # of files copied is greater than 1 digit) and checking the ascii value until we don't get a number';
   PRINT N'';
   PRINT N'	   declare @index int';
   PRINT N'	          ,@temp char;';
   PRINT N'';
   PRINT N'	   set @index = datalength(@message) / 2;';
   PRINT N'	   set @temp = substring(@message, @index, 1)';
   PRINT N'	   set @numCopied = '';';
   PRINT N'';
   PRINT N'	   while(ascii(@temp) > 47 and ascii(@temp) < 58)begin';
   PRINT N'	      ';
   PRINT N'	      set @numCopied = @temp + @numCopied --append the new number to @numCopied';
   PRINT N'	      set @index = @index - 1;';
   PRINT N'	      set @temp = substring(@message, @index, 1)';
   PRINT N'';
   PRINT N'	   end;';
   PRINT N'';
   PRINT N'	   PRINT N'	Number of files copied: ' + @numCopied;';
   PRINT N'';
   PRINT N'	end';
   PRINT N'	else begin';
   PRINT N'	   PRINT N'	Job failed';';
   PRINT N'	end;';
   PRINT N'';
   PRINT N'	-- If the number of files copied is nonzero, check LS.secondary for the backup and check to ensure it is the tail like we have been doing';
   PRINT N'	-- Remembering to check the initial @lastCopiedFile to LS.last_copied_file, knowing now that a new one should be in the table eventually';
   PRINT N'';


   PRINT N'';
   PRINT N'	-- Start the check for the restore job';
   PRINT N'';
   PRINT N'';
   PRINT N'	declare @initialRestore nvarchar(500);';
   PRINT N'';
   PRINT N'	SELECT';
   PRINT N'	   @initialRestore = lssd.last_restored_file';
   PRINT N'	FROM';
   PRINT N'	   log_shipping_secondary_databases AS lssd';
   PRINT N'	WHERE';
   PRINT N'	   lssd.secondary_database = 'LogshipTest_1'';
   PRINT N'';
   PRINT N'	print 'initial: ' + @initialRestore';
   PRINT N'';
   PRINT N'	-- get the initial count(*) for MHD';
   PRINT N'';
   PRINT N'	select ';
   PRINT N'	   @beforeLogCount = Count(*)';
   PRINT N'	from ';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	set @beginTest = current_timestamp';
   PRINT N'';
   PRINT N'	print 'before: ' + @beforeLogCount';
   PRINT N'';
   PRINT N'	-- start the restore job';
   PRINT N'';
   PRINT N'	exec sp_start_job @job_name = 'LSRestore_sql-logship-p_LogshipTest_1'';
   PRINT N'';
   PRINT N'	--start the timer';
   PRINT N'';
   PRINT N'	set @start = current_timestamp';
   PRINT N'';
   PRINT N'	-- get the current count(*) for MHD';
   PRINT N'';
   PRINT N'	select';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	from';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	print 'right after: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	-- wait for MHD to get updated';
   PRINT N'';
   PRINT N'	while(@afterLogCount = @beforeLogCount)BEGIN';
   PRINT N'';
   PRINT N'	   select';
   PRINT N'	      @afterLogCount = Count(*)';
   PRINT N'	   from';
   PRINT N'	      log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	   print 'during: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	   waitfor delay '00:00:1';';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	-- Wait for all of the rows to be inserted into MHD from the copy job's run';
   PRINT N'';
   PRINT N'	select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc';
   PRINT N'';
   PRINT N'	--We'll  need to change this to @beforeLogCount != 0 || 1 since a job can end on 2, 3 or 4 (success, error, warning)';
   PRINT N'';
   PRINT N'	while(@session = 0 or @session = 1)BEGIN';
   PRINT N'';
   PRINT N'	print 'session: ' + @session';
   PRINT N'';
   PRINT N'	   waitfor delay '00:00:1'';
   PRINT N'';
   PRINT N'	   select top 1 @session = session_status from log_shipping_monitor_history_detail order by log_time desc';
   PRINT N'';
   PRINT N'	END;';
   PRINT N'';
   PRINT N'	--getting the final count(*) just to make sure the previous worked correctly';
   PRINT N'';
   PRINT N'	select';
   PRINT N'	   @afterLogCount = Count(*)';
   PRINT N'	from';
   PRINT N'	   log_shipping_monitor_history_detail';
   PRINT N'';
   PRINT N'	print 'finished: ' + @afterLogCount';
   PRINT N'';
   PRINT N'	set @stop = current_timestamp';
   PRINT N'';
   PRINT N'	print datediff(s, @start, @stop)';
   PRINT N'';
   PRINT N'	--Determine if the restore job restored anything';
   PRINT N'';
   PRINT N'	declare @numRestored nvarchar(10)';
   PRINT N'';
   PRINT N'	if(@session = 2)begin';
   PRINT N'';
   PRINT N'	   -- The # of logs restored isn't as simple to access as it was for the copy jobs, as it is one of the potentially numerous 1 session_status rows';
   PRINT N'	   -- So we're grabbing all of the rows inserted after our timestamp (which will only be rows for the restore job we ran) and finding the one that has our information';
   PRINT N'';
   PRINT N'	   select  ';
   PRINT N'	      @message = rtrim(l.message)';
   PRINT N'	   from ';
   PRINT N'	      log_shipping_monitor_history_detail as l';
   PRINT N'	   where';
   PRINT N'	      log_time > @start';
   PRINT N'	      and message like '%Number of log backup files restored:%'';
   PRINT N'';
   PRINT N'	   -- We're starting at the right side of the message taking one char at a time (incase the # of files copied is greater than 1 digit) and checking the ascii value until we don't get a number';
   PRINT N'';
   PRINT N'	   set @index = datalength(@message) / 2;';
   PRINT N'	   set @temp = substring(@message, @index, 1)';
   PRINT N'	   set @numRestored = '';';
   PRINT N'';
   PRINT N'	   while(ascii(@temp) > 47 and ascii(@temp) < 58)begin';
   PRINT N'	      ';
   PRINT N'	      set @numRestored = @temp + @numRestored --append the new number to @numCopied';
   PRINT N'	      set @index = @index - 1;';
   PRINT N'	      set @temp = substring(@message, @index, 1)';
   PRINT N'';
   PRINT N'	   end;';
   PRINT N'';
   PRINT N'	   PRINT N'	Number of files restored: ' + @numRestored;';
   PRINT N'';
   PRINT N'	end';
   PRINT N'	else begin';
   PRINT N'	   PRINT N'	Job failed';';
   PRINT N'	end;';
   PRINT N'';
   PRINT N'	-- If the number of restored logs is nonzero we check backupset to ensure the log was the tail backup';
   PRINT N'	-- We start by ensuring the table is fully up to date by checking how many rows have been inserted since we started our timer';
   PRINT N'	-- From testing it looks like backupset is up to date at this point, but we'll keep the check in anyway';
   PRINT N'';
   PRINT N'	while((select count(*) from backupset as b where b.backup_start_date > @start) > cast(@numRestored as int))begin';
   PRINT N'	   ';
   PRINT N'	   print 'Waiting for backupset...';';
   PRINT N'	   waitfor delay '00:00:01'';
   PRINT N'';
   PRINT N'	end;