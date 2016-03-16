/*

This script is ran on the primary server of your logshipping configuration after primary logshipping has been setup

Use this script to produce a T-SQL script to recreate databases and their respective permissions on the secondary instance of your logshipping configuration

*/
 
--
-- Start of recreate databases script
--

--================================================================
set nocount on;

-- @dbNames contains the set of databases that we will be creating along with their principals

declare @dbNames table (
   name sysname not null primary key
 , owner_name sysname null
 , [compatibility_level] tinyint                -- 70; 80; 90
 , is_fulltext_enabled bit                      -- 1 = on; 0 = off
 , is_ansi_null_default_on bit                  -- 1 = on; 0 = off
 , is_ansi_nulls_on bit                         -- 1 = on; 0 = off
 , is_ansi_padding_on bit                       -- 1 = on; 0 = off
 , is_ansi_warnings_on bit                      -- 1 = on; 0 = off
 , is_arithabort_on bit                         -- 1 = on; 0 = off
 , is_auto_close_on bit                         -- 1 = on; 0 = off
 , is_auto_create_stats_on bit                  -- 1 = on; 0 = off
 , is_auto_shrink_on bit                        -- 1 = on; 0 = off
 , is_auto_update_stats_on bit                  -- 1 = on; 0 = off
 , is_cursor_close_on_commit_on bit             -- 1 = on; 0 = off
 , is_local_cursor_default bit                  -- 1 = local; 0 = global
 , is_concat_null_yields_null_on bit            -- 1 = on; 0 = off
 , is_numeric_roundabort_on bit                 -- 1 = on; 0 = off
 , is_quoted_identifier_on bit                  -- 1 = on; 0 = off
 , is_recursive_triggers_on bit                 -- 1 = on; 0 = off
 , is_broker_enabled bit                        -- 1 = ""; 0 = disable_broker
 , is_auto_update_stats_async_on bit            -- 1 = on; 0 = off
 , is_date_correlation_on bit                   -- 1 = on; 0 = off
 , is_trustworthy_on bit                        -- 1 = on; 0 = off
 , snapshot_isolation_state_desc nvarchar(60)   -- off, on, in_transition_to_on, in_transition_to_off
 , is_parameterization_forced bit               -- 1 = forced; 0 = simple
 , is_read_committed_snapshot_on bit            -- 1 = on; 0 = off
 , recovery_model_desc nvarchar(60)             -- full; bulk_logged, simple
 , user_access_desc nvarchar(60)                -- multi_user; single_user; restricted_user
 , page_verify_option_desc nvarchar(60)         -- none, torn_page_detection, checksum
 , is_db_chaining_on bit                        -- 1 = on; 0 = off
 , is_read_only bit                             -- 1 = read_only; 0 = read_write
 , state_desc nvarchar(60)                      -- ONLINE, RESTORING, RECOVERING, RECOVERY_PENDING, SUSPECT, EMERGENCY, OFFLINE
 , collation_name sysname null
);

-- @dbFiles holds information about the database files

declare @dbFiles table (
   database_name sysname
 , data_space_name sysname null
 , file_type tinyint
 , file_type_desc nvarchar(60)
 , data_file_name sysname
 , physical_name nvarchar(260)
 , size int
 , max_size int
 , is_percent_growth bit
 , growth int
 , is_default bit
 , rowID int
 , fileGroupRowID int
 , filespec as (N'( name = N''' + data_file_name + N''''
              + N', filename = N''' + physical_name + N''''
              + N', size = ' + cast((size * cast(8 as bigint) 
                                   / case when size >= 268435456 then 1048576 else 1 end) 
                                   as nvarchar(40)) 
                             + case when size > 268435456 then N'GB' else N'KB' end
              + N', maxsize = ' + case when max_size = -1 then N'unlimited' 
                                       else cast((max_size * cast(8 as bigint) 
                                                / case when max_size >= 268435456 then 1048576 else 1 end) 
                                                as nvarchar(40)) 
                                          + case when max_size >= 268435456 then N'GB' else N'KB' end 
                                  end 
              + N', filegrowth = ' + case when is_percent_growth = 1 then cast(growth as nvarchar(3)) + N'%' 
                                          else cast((growth * cast(8 as bigint) 
                                                   / case when growth >= 268435456 then 1048576 else 1 end)
                                                   as nvarchar(40)) 
                                             + case when growth >= 268435456 then N'GB' else N'KB' end 
                                     end
              + N' )')
);

declare @tab nchar(3);
declare @crlf nchar(2);
declare @dbName sysname
 , @compatibility_level tinyint                 -- 70; 80; 90
 , @owner_name sysname
 , @is_fulltext_enabled bit                     -- 1 = on; 0 = off
 , @is_ansi_null_default_on bit                 -- 1 = on; 0 = off
 , @is_ansi_nulls_on bit                        -- 1 = on; 0 = off
 , @is_ansi_padding_on bit                      -- 1 = on; 0 = off
 , @is_ansi_warnings_on bit                     -- 1 = on; 0 = off
 , @is_arithabort_on bit                        -- 1 = on; 0 = off
 , @is_auto_close_on bit                        -- 1 = on; 0 = off
 , @is_auto_create_stats_on bit                 -- 1 = on; 0 = off
 , @is_auto_shrink_on bit                       -- 1 = on; 0 = off
 , @is_auto_update_stats_on bit                 -- 1 = on; 0 = off
 , @is_cursor_close_on_commit_on bit            -- 1 = on; 0 = off
 , @is_local_cursor_default bit                 -- 1 = local; 0 = global
 , @is_concat_null_yields_null_on bit           -- 1 = on; 0 = off
 , @is_numeric_roundabort_on bit                -- 1 = on; 0 = off
 , @is_quoted_identifier_on bit                 -- 1 = on; 0 = off
 , @is_recursive_triggers_on bit                -- 1 = on; 0 = off
 , @is_broker_enabled bit                       -- 1 = ""; 0 = disable_broker
 , @is_auto_update_stats_async_on bit           -- 1 = on; 0 = off
 , @is_date_correlation_on bit                  -- 1 = on; 0 = off
 , @is_trustworthy_on bit                       -- 1 = on; 0 = off
 , @snapshot_isolation_state_desc nvarchar(60)  -- off, on, in_transition_to_on, in_transition_to_off
 , @is_parameterization_forced bit              -- 1 = forced; 0 = simple
 , @is_read_committed_snapshot_on bit           -- 1 = on; 0 = off
 , @recovery_model_desc nvarchar(60)            -- full; bulk_logged, simple
 , @user_access_desc nvarchar(60)               -- multi_user; single_user; restricted_user
 , @page_verify_option_desc nvarchar(60)        -- none, torn_page_detection, checksum
 , @is_db_chaining_on bit                       -- 1 = on; 0 = off
 , @is_read_only bit                            -- 1 = read_only; 0 = read_write
 , @state_desc nvarchar(60)                     -- ONLINE, RESTORING, RECOVERING, RECOVERY_PENDING, SUSPECT, EMERGENCY, OFFLINE
 , @collation_name sysname
;

declare @cmd nvarchar(max);
declare @rowID int;
declare @filespec nvarchar(4000);
declare @data_space_name sysname;
declare @new_file_group bit;
declare @fileGroupRowID int;
declare @is_default bit;

set @tab = N'   ';
set @crlf = nchar(13) + nchar(10);

insert into @dbNames
   (name, owner_name, [compatibility_level], is_fulltext_enabled, is_ansi_null_default_on, is_ansi_nulls_on, is_ansi_padding_on
   , is_ansi_warnings_on, is_arithabort_on, is_auto_close_on, is_auto_create_stats_on, is_auto_shrink_on
   , is_auto_update_stats_on, is_cursor_close_on_commit_on, is_local_cursor_default, is_concat_null_yields_null_on
   , is_numeric_roundabort_on, is_quoted_identifier_on, is_recursive_triggers_on, is_broker_enabled
   , is_auto_update_stats_async_on, is_date_correlation_on, is_trustworthy_on, snapshot_isolation_state_desc
   , is_parameterization_forced, is_read_committed_snapshot_on, recovery_model_desc, user_access_desc
   , page_verify_option_desc, is_db_chaining_on, is_read_only, state_desc, collation_name)
select   d.name
       , sp.name
       , [compatibility_level]
       , is_fulltext_enabled
       , is_ansi_null_default_on
       , is_ansi_nulls_on
       , is_ansi_padding_on
       , is_ansi_warnings_on
       , is_arithabort_on
       , is_auto_close_on
       , is_auto_create_stats_on
       , is_auto_shrink_on
       , is_auto_update_stats_on
       , is_cursor_close_on_commit_on
       , is_local_cursor_default
       , is_concat_null_yields_null_on
       , is_numeric_roundabort_on
       , is_quoted_identifier_on
       , is_recursive_triggers_on
       , is_broker_enabled
       , is_auto_update_stats_async_on
       , is_date_correlation_on
       , is_trustworthy_on
       , snapshot_isolation_state_desc
       , is_parameterization_forced
       , is_read_committed_snapshot_on
       , recovery_model_desc
       , user_access_desc
       , page_verify_option_desc
       , is_db_chaining_on
       , is_read_only
       , state_desc
       , collation_name
from     msdb.dbo.log_shipping_primary_databases as lspd -- This filters to only primary logshipping databases
         left join sys.databases as d on lspd.primary_database = d.name
         left outer join sys.server_principals as sp on d.owner_sid = sp.sid       
order by d.name;

-- For debugging purposes

select   *
from     @dbNames as dn
order by name;

-- Print database creation header information

declare @secondaryServer sysname;
select top 1 @secondaryServer = secondary_server from msdb.dbo.log_shipping_primary_secondaries;

print N'/*';
print N' * *****RUN ON ' + quotename(@secondaryServer) + N'*****';
print N' * Use the following script to produce a T-SQL script to recreate primary instance databases on the secondary instance of a logshipping configuration';
print N' *';
print N' * Generated ' + convert(varchar, getdate()) + N' by ' + suser_sname();
print N' *';

set @dbName = N'';

if (not exists(select * from @dbNames)) begin

   print N' * ! No primary logshipping databases to be recreated found!';
   print N' *';

end else begin
		
   print N' * Databases created by this script:';

   set @dbName = N'';

   while (exists(select * from @dbNames where (name > @dbName))) begin
  
      select   top 1
               @dbName = name
      from     @dbNames as dn
      where    (name > @dbName)
      order by name;

      print N' * ' + @tab + @dbName;

   end; 

   print N' *';

end;

print N' */';
print N'';

print N'use [master];';
print N'go';
print N'';
PRINT N'-- #elapsedTimeAndFilePath is used to keep track of the total execution time of the script';
PRINT N'';
PRINT N'IF OBJECT_ID(''tempdb.dbo.#elapsedTime'', ''U'') IS NOT NULL';
PRINT N'    DROP TABLE #elapsedTime';
PRINT N'';
PRINT N'CREATE TABLE #elapsedTime (timestamps DATETIME);';
PRINT N'';
PRINT N'INSERT INTO #elapsedTime SELECT CURRENT_TIMESTAMP;';
PRINT N'';

set @dbName = N'';

while (exists(select * from @dbNames where (name > @dbName))) begin

   select   top 1
            @dbName = name
          , @owner_name = owner_name
          , @compatibility_level = [compatibility_level]
          , @is_fulltext_enabled = is_fulltext_enabled
          , @is_ansi_null_default_on = is_ansi_null_default_on
          , @is_ansi_nulls_on = is_ansi_nulls_on
          , @is_ansi_padding_on = is_ansi_padding_on
          , @is_ansi_warnings_on = is_ansi_warnings_on
          , @is_arithabort_on = is_arithabort_on
          , @is_auto_close_on = is_auto_close_on
          , @is_auto_create_stats_on = is_auto_create_stats_on
          , @is_auto_shrink_on = is_auto_shrink_on
          , @is_auto_update_stats_on = is_auto_update_stats_on
          , @is_cursor_close_on_commit_on = is_cursor_close_on_commit_on
          , @is_local_cursor_default = is_local_cursor_default
          , @is_concat_null_yields_null_on = is_concat_null_yields_null_on
          , @is_numeric_roundabort_on = is_numeric_roundabort_on
          , @is_quoted_identifier_on = is_quoted_identifier_on
          , @is_recursive_triggers_on = is_recursive_triggers_on
          , @is_broker_enabled = is_broker_enabled
          , @is_auto_update_stats_async_on = is_auto_update_stats_async_on
          , @is_date_correlation_on = is_date_correlation_on
          , @is_trustworthy_on = is_trustworthy_on
          , @snapshot_isolation_state_desc = snapshot_isolation_state_desc
          , @is_parameterization_forced = is_parameterization_forced
          , @is_read_committed_snapshot_on = is_read_committed_snapshot_on
          , @recovery_model_desc = recovery_model_desc
          , @user_access_desc = user_access_desc
          , @page_verify_option_desc = page_verify_option_desc
          , @is_db_chaining_on = is_db_chaining_on
          , @is_read_only = is_read_only
          , @state_desc = state_desc
          , @collation_name = collation_name
   from     @dbNames as dn
   where    (name > @dbName)
   order by name;

   -- Inserting into @dbFiles

   set @cmd = replace(replace(N'select   N''{database_name}'' as database_name
       , ds.name as data_space_name
       , df.type as file_type
       , df.type_desc as file_type_desc
       , df.name as data_file_name
       , physical_name
       , size
       , max_size
       , is_percent_growth
       , growth
       , ds.is_default
       , row_number() over(order by case when ds.name = N''PRIMARY'' then 1 else 2 end, df.[type], df.[file_id]) as rowID
       , row_number() over(partition by ds.name order by df.[file_id]) as fileGroupRowID
from     {quoted_database_name}.sys.database_files as df 
         left outer join {quoted_database_name}.sys.data_spaces as ds on df.data_space_id = ds.data_space_id
where    (df.[type] <> 4) -- ignore fulltext
order by case when ds.name = N''PRIMARY'' then 1 else 2 end
       , df.[type]
       , df.[file_id];'
       , N'{database_name}', @dbName)
       , N'{quoted_database_name}', quotename(@dbName));

   insert into @dbFiles
      (database_name, data_space_name, file_type, file_type_desc, data_file_name, physical_name, size, max_size, is_percent_growth, growth, is_default, rowID, fileGroupRowID) 
   exec ( @cmd );

   print N'--';
   print N'--============================================================';
   print N'--';
   print N'';
   print N'print N''--============================================================'';';
   print N'print N''Begin Database: ' + quotename(@dbName) + N''';';
   print N'go';
   print N'';

   print N'print N''creating database ' + quotename(@dbName) + N'...'';';
   print N'';
   print N'go';
   print N'';
   print N'create database ' + quotename(@dbName) + N' on';
   
   set @rowID = 0;
   set @new_file_group = 1;
   set @data_space_name = N'';

   -- Start outputting the create database code

   while exists(select * from @dbFiles where (database_name = @dbName) and (file_type = 0) and (rowID > @rowID)) begin
  
      select   top 1
               @rowID = rowID
             , @filespec = filespec
             , @new_file_group = case when @data_space_name <> data_space_name then 1 else 0 end
             , @data_space_name = data_space_name
             , @fileGroupRowID = fileGroupRowID
             , @is_default = coalesce(is_default, 0)
      from     @dbFiles
      where    (database_name = @dbName)
               and (file_type = 0)
               and (rowID > @rowID) 
      order by rowID;

      if (@new_file_group = 1) begin
         print case when @rowID = 1 then @tab else N' , ' end 
             + case when @data_space_name = N'PRIMARY' then @data_space_name 
                  else N'filegroup ' + quotename(@data_space_name) + case when @is_default = 1 then N' default' else N'' end
               end ;
      end;

      print @tab + case when @fileGroupRowID = 1 then @tab else ' , ' end + @filespec;

   end; 

   print @tab + N'log on ';
   
   set @rowID = 0;
   set @filespec = N'';

   while exists(select * from @dbFiles where (database_name = @dbName) and (file_type = 1) and (rowID > @rowID)) begin
  
      select   top 1
               @rowID = rowID
             , @filespec = filespec
             , @fileGroupRowID = fileGroupRowID
      from     @dbFiles
      where    (database_name = @dbName)
               and (file_type = 1)
               and (rowID > @rowID) 
      order by rowID;
  
      print @tab + case when @fileGroupRowID = 1 then @tab else ' , ' end + @filespec;

   end; 

   if (@collation_name is not null) begin
      print @tab + N'collate ' + @collation_name;
   end;

   print @tab + N';';

   -- Set database options

   print N'go';
   print N'print N''setting compatibility level for ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'exec dbo.sp_dbcmptlevel @dbname=N''' + @dbName + N''', @new_cmptlevel=' + cast(@compatibility_level as nvarchar(3)) + N';';
   print N'go';
   print N'print N''setting full text state for ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'if (fulltextserviceproperty(N''IsFullTextInstalled'') = 1) begin';
   print @tab + N'exec ' + quotename(@dbName) + '.dbo.sp_fulltext_database @action=''' + case when @is_fulltext_enabled = 1 then N'enable' else N'disable' end + N''';';
   print N'end;';
   print N'go';
   print N'print N''setting database options for ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ' + @state_desc + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ' + @user_access_desc + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ' + case @is_read_only when 1 then N'read_only' else N'read_write' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set db_chaining ' + case @is_db_chaining_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set trustworthy ' + case @is_trustworthy_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set cursor_close_on_commit ' + case @is_cursor_close_on_commit_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set cursor_default ' + case @is_local_cursor_default when 1 then N'local' else N'global' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set auto_close ' + case @is_auto_close_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set auto_create_statistics ' + case @is_auto_create_stats_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set auto_shrink ' + case @is_auto_shrink_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set auto_update_statistics ' + case @is_auto_update_stats_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set auto_update_statistics_async ' + case @is_auto_update_stats_async_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ansi_null_default ' + case @is_ansi_null_default_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ansi_nulls ' + case @is_ansi_nulls_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ansi_padding ' + case @is_ansi_padding_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ansi_warnings ' + case @is_ansi_warnings_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set arithabort ' + case @is_arithabort_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set concat_null_yields_null ' + case @is_concat_null_yields_null_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set numeric_roundabort ' + case @is_numeric_roundabort_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set quoted_identifier ' + case @is_quoted_identifier_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set recursive_triggers ' + case @is_recursive_triggers_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set recovery ' + @recovery_model_desc + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set page_verify ' + @page_verify_option_desc + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set ' + case @is_broker_enabled when 1 then N'enable_broker' else N'disable_broker' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set date_correlation_optimization ' + case @is_date_correlation_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set parameterization ' + case @is_parameterization_forced when 1 then N'forced' else N'simple' end + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set allow_snapshot_isolation ' + @snapshot_isolation_state_desc + N';';
   print N'go';
   print N'alter database ' + quotename(@dbName) + N' set read_committed_snapshot ' + case @is_read_committed_snapshot_on when 1 then N'on' else N'off' end + N';';
   print N'go';
   print N'';

   if (@owner_name is not null) begin

      print N'print N''setting database owner for ' + quotename(@dbName) + N'...'';'; 
      print N''; 
      print N'if (exists(select * from [master].sys.server_principals where name = N''' + @owner_name + N''')) begin'
      print @tab + N'alter authorization on database::' + quotename(@dbName) + N' to ' + quotename(@owner_name) + N';';
      print N'end else begin';
      print @tab + N'raiserror (N''Unable to find login ' + quotename(@owner_name) + N' to set owner of database ' + quotename(@dbName) + N'!'', 16, 1);';
      print N'end;';
      print N'go';
  
   end; 

   print N'print N''End Database: ' + quotename(@dbName) + N'. Beginning Principal Creation...'';';
   print N'';
   print N'go';
   print N'';

   raiserror(N'',0,1) WITH NOWAIT; -- flush print buffer;

   --
   -- End of recreate database script
   --================================================================
   --


   --
   -- Begin recreating database permissions
   --================================================================
   --

   /*

   This portion of the script produces a T-SQL script to recreate database principals from the current instance matching filters, 
   optionally also recreating the corresponding server principal and rights.

   Specify the database context in the use statement below to inspect the desired database.

   */

   --We use dynamic SQL here as it is necessary to change database context for each database we iterate through

   declare @useCmd nvarchar(MAX);
   set @useCmd = N'use ' + @dbName + N';';

   set @useCmd = @useCMD + '

   set nocount on;
   declare @debug bit;
   declare @principal_name nvarchar(128);
   declare @include_role_members bit;
   declare @include_role_parents bit;
   declare @include_system_objects bit;
   declare @recreate_logins bit;
   declare @compatibility_level_prncpl int;

   set @compatibility_level_prncpl = 90;
   set @debug = 0;

   set @include_role_members = 0;
   set @include_role_parents = 1;
   set @include_system_objects = 0;
   set @recreate_logins = 1;

   --set @principal_name = N'''';

   --set @principal_name = N''tsgUser'';

   --set @principal_name = N''CBCSyncUser'';
   --set @principal_name = N''GCF Applications'';
   --SET @principal_name = N''Budget Users'';
   --set @principal_name = N''SQLMonitorUser'';
   --set @principal_name = N''MergeImportUser'';
   --set @principal_name = N''PBRC\StewarAE'';
   --set @principal_name = N''StudyManagerUser'';
   --set @principal_name = N''Email Creators'';
   --set @principal_name = N''CBCSyncUsers'';
   --set @principal_name = N''ChamberUser'';
   --set @principal_name = N''Email Readers - BRC'';
   --set @principal_name = N''PINE Application'';
   --set @principal_name = N''LinkedServerBrowsers'';
   --set @principal_name = N''LACaTSUser'';
   --set @principal_name = N''email readers'';
   --set @principal_name = N''Log Readers'';
   --set @principal_name = N''WebApplication'';
   --set @principal_name = N''pbrc\turnerdg'';
   --set @principal_name = N''pbrc\davenpfg''
   --set @principal_name = N''pbrc\RuthJG'';
   --set @principal_name = N''pbrc\nguyenvl'';
   --set @principal_name = N''pbrc\kellyjl'';
   --set @principal_name = N''pbrc\mossvl''
   --set @principal_name = N''pbrc\nguyenth'';
   --set @principal_name = N''LinkUser''
   --set @principal_name = N''acg developers''
   --set @principal_name = N''PublicWeb Users'' ;
   --set @principal_name = N''PublicApplicationUsers'' ;
   --set @principal_name = N''PublicApplicationOperators'' ;
   
   -- =============================================

   set @debug = coalesce(@debug, 0);

   set @principal_name = nullif(@principal_name, N'''');

   if (@principal_name is not null) 
      set @principal_name = coalesce((select name
                                      from   sys.database_principals
                                      where  name = @principal_name
                                     ), @principal_name) ;

   set @include_role_members = coalesce(@include_role_members, 0);   

   set @include_system_objects = coalesce(@include_system_objects, 0);

   set @recreate_logins = coalesce(@recreate_logins, 0);
	
   if (object_id(''tempdb..#target_principals'') is not null)
      drop table #target_principals;	

   if (object_id(''tempdb..#server_principals'') is not null)
      drop table #server_principals;

   if (object_id(''tempdb..#server_permissions'') is not null)
      drop table #server_permissions;

   if (object_id(''tempdb..#server_memberships'') is not null)
      drop table #server_memberships;
	
   if (object_id(''tempdb..#database_principals'') is not null)
      drop table #database_principals;	

   if (object_id(''tempdb..#database_permissions'') is not null)
	   drop table #database_permissions;

   if (object_id(''tempdb..#database_roles'') is not null)
      drop table #database_roles;

   if (object_id(''tempdb..#database_memberships'') is not null)
	   drop table #database_memberships;

   create table #target_principals (
      principal_id int primary key clustered
   );

   create table #server_principals (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , [sid] varbinary(85)
    , server_principal_name nvarchar(128)
    , principal_type_sort_order tinyint
    , password_hash varbinary(256)
    , isntname bit
    , default_database_name nvarchar(128)
   );

   create table #server_permissions (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , [object_name] nvarchar(128)
    , principal_type_sort tinyint
    , permission_class tinyint
    , permission_class_description nvarchar(60)
    , major_id int
    , minor_id int
    , principal_id int
    , principal_name nvarchar(128)
    , principal_type_description nvarchar(60)
    , permission_type char(4)
    , [permission_name] nvarchar(128)
    , permission_state_description nvarchar(60)
    , grantor_principal_id int
    , grantor_name nvarchar(128)
   );

   create table #server_memberships (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , member_principal_name nvarchar(128)
    , server_principal_name nvarchar(128)
    , principal_type_sort_order tinyint
    , principal_type_description nvarchar(60)
    , role_name nvarchar(128)
    , principal_id int
    , [sid] varbinary(85)
   );

   create table #database_principals (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , [user_name] nvarchar(128)
    , principal_id int
    , login_name nvarchar(128)
    , default_schema_name nvarchar(128)
   );

   create table #database_roles (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , role_name nvarchar(128)
    , principal_id int
    , owner_name nvarchar(128)
   );

   create table #database_memberships (
      RowID int not null identity (1, 1) primary key clustered
    , cmd nvarchar(max)
    , member_principal_id int
    , member_type_sort_order tinyint
    , member_principal_name nvarchar(128)
    , role_principal_id int
    , role_principal_name nvarchar(128)
    , is_fixed_role bit
   );

   create table #database_permissions (
      RowID int not null identity(1, 1) primary key clustered
    , cmd nvarchar(max)
    , [schema_name] nvarchar(128)
    , [object_name] nvarchar(128)
    , column_name nvarchar(128)
    , principal_type_sort tinyint
    , permission_class tinyint
    , permission_class_description nvarchar(60)
    , major_id int
    , minor_id int
    , principal_id int
    , principal_name nvarchar(128)
    , principal_type_description nvarchar(60)
    , permission_type char(4)
    , [permission_name] nvarchar(128)
    , permission_state_description nvarchar(60)
    , grantor_principal_id int
    , grantor_name nvarchar(128)
   );

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''getting target principals...'', 0, 1) with nowait;

   end;

   if (@principal_name is null) begin

      -- include all principals
      insert into #target_principals 
         (principal_id)
      select   dp.principal_id
      from     sys.database_principals as dp
      where    (dp.[sid] <> 0x01) -- don''t want sa/dbo;

   end else begin

      with all_principals as (
         -- anchor with the specified principal''s explicit roles
         select   drm.member_principal_id
                , drm.role_principal_id
         from     sys.database_role_members as drm
                  inner join sys.database_principals as dp on drm.member_principal_id = dp.principal_id
         where    (dp.[name] = coalesce(@principal_name, dp.[name]))
         union all
         -- recurse to all roles of which those roles are a member
         select   drm.member_principal_id
                , drm.role_principal_id
         from     all_principals
                  inner join sys.database_role_members as drm on all_principals.role_principal_id = drm.member_principal_id
         where    (@include_role_parents = 1)
      )
      insert into #target_principals (
         principal_id
      )
      -- include the specified principal explicitly, in case they aren''t a member of any roles
      select   principal_id
      from     sys.database_principals as dp
      where    (dp.[name] = coalesce(@principal_name, dp.[name]))
      union
      -- include the principals found
      select   dp.principal_id
      from     all_principals
               inner join sys.database_principals as dp on all_principals.member_principal_id = dp.principal_id
      union
      -- include any roles that the principals are a member of
      select   dp.principal_id
      from     all_principals
               inner join sys.database_principals as dp on all_principals.role_principal_id = dp.principal_id
      where    (@include_role_parents = 1);

   end;

   if (@include_role_members = 1) begin

      with all_members as (
         select   drm.member_principal_id
                , drm.role_principal_id
         from     #target_principals as p
                  inner join sys.database_role_members as drm on p.principal_id = drm.role_principal_id
         union all
         select   drm.member_principal_id
                , drm.role_principal_id
         from     all_members
                  inner join sys.database_role_members as drm on all_members.member_principal_id = drm.role_principal_id
      )
      insert into #target_principals (
         principal_id
      )
      select   distinct 
               dp.principal_id
      from     all_members
               inner join sys.database_principals as dp on all_members.member_principal_id = dp.principal_id
      where    (dp.principal_id not in (select principal_id from #target_principals))
               and (dp.[sid] <> 0x01) -- don''t want sa/dbo;
   
   end

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''showing target principals...'', 0, 1) with nowait;

      select   sp.*
      from     #target_principals as p2
               inner join sys.database_principals as dp on p2.principal_id = dp.principal_id
               inner join sys.server_principals as sp on dp.[sid] = sp.[sid]
      where    (dp.[sid] is not null)  
               and (dp.is_fixed_role = 0)
      order by case sp.[type]
                 when ''S'' then 1 -- sql user
                 when ''U'' then 2 -- windows user
                 when ''G'' then 3 -- windows group
                 when ''A'' then 4 -- application role
                 when ''R'' then 5 -- database role
                 when ''C'' then 6 -- user mapped to a certificate
                 when ''K'' then 7 -- user mapped to an asymmetric key                                
               end
             , sp.name;

   end;
   
   if (@recreate_logins = 1) begin

      if (@debug = 1) begin

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''getting server principals...'', 0, 1) with nowait;

      end;

      declare @x xml;

      set @x = N''<root></root>'';

      insert into #server_principals (
         cmd
       , [sid]
       , server_principal_name
       , password_hash
       , isntname
       , default_database_name
       , principal_type_sort_order
      )
      select   replace(replace(replace(
                  N''if not exists (select * from sys.server_principals where [name] = N''''{server_principal_name}'''')|   create login {quoted_server_principal_name}{specification};|''
                , N''{server_principal_name}'', sp.[name])
                , N''{quoted_server_principal_name}'', quotename(sp.[name]))
                , N''{specification}'', case sp.[type] 
                                       when ''S'' 
                                          then replace(replace(replace(replace(replace(replace(
                                                  N'' with password={password}{hashed}, check_expiration={check_expiration}, check_policy={check_policy}, sid={sid}, default_database={quoted_default_database_name}''
                                                , N''{quoted_default_database_name}'', quotename(sp.default_database_name))
                                                , N''{sid}'', ct.sid_ct)
                                                , N''{check_policy}'', case sl.is_policy_checked when 1 then N''on'' else N''off'' end)
                                                , N''{check_expiration}'', case is_expiration_checked when 1 then N''on'' else N''off'' end)
                                                , N''{hashed}'', case when ct.password_ct is null then N'''' else N'' hashed'' end)
                                                , N''{password}'', case when ct.password_ct is null then N'''' else password_ct end
                                               )
                                       else replace(
                                               N'' from windows with default_database={quoted_default_database_name}''
                                             , N''{quoted_default_database_name}'', quotename(sp.default_database_name)
                                            )
                                    end
               ) as cmd
             , sp.[sid]
             , sp.[name]
             , sl.password_hash              
             , case sl.[type] when ''S'' then 0 else 1 end as isntname
             , sp.default_database_name
             , ptso.principal_type_sort_order
      from     #target_principals as p 
               inner join sys.database_principals as dp on p.principal_id = dp.principal_id
               left join [master].sys.server_principals as sp on dp.[sid] = sp.[sid]
               left join sys.sql_logins as sl on dp.[sid] = sl.[sid]
               --outer apply (
               --            select sys.fn_varbintohexstr(sl.password_hash) as password_ct
               --                   , sys.fn_varbintohexstr(sp.[sid]) as sid_ct
               --            ) as ct
               outer apply (
                  select
                     N''0x'' + @x.value(N''xs:hexBinary(sql:column("sl.password_hash"))'', N''[nvarchar](512)'') as password_ct
                   , N''0x'' + @x.value(N''xs:hexBinary(sql:column("sp.[sid]"))'', N''[nvarchar](512)'')         as sid_ct      
               ) as ct
               outer apply (
                           select case sp.[type]
                                   when ''S'' then 1 -- sql user
                                   when ''U'' then 2 -- windows user
                                 end as principal_type_sort_order) as ptso
      where    (sp.[type] in (''S'', ''U''))
               and (sp.is_disabled = 0)
               and (sp.[sid] <> 0x01) -- don''t want sa/dbo
      order by ptso.principal_type_sort_order
             , sp.[name];

      if (@debug = 1) begin

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''showing server principals...'', 0, 1) with nowait;

         select   *
         from     #server_principals as l
         order by RowID ;

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''getting server role memberships...'', 0, 1) with nowait;

      end;

      insert into #server_memberships (
         cmd
       , member_principal_name
       , server_principal_name
       , principal_type_sort_order
       , principal_type_description
       , role_name, principal_id
       , [sid]
      )
      select   replace(replace(replace(replace(
                  N''if exists(select * from sys.server_principals where name = N''''{member_principal_name}'''')|    '' + 
                  case when @compatibility_level_prncpl < 110 
                     then N''exec dbo.sp_addsrvrolemember @loginame = N''''{member_principal_name}'''', @rolename = N''''{role_name}'''';''
                     else N''alter server role {quoted_role_name} add member {quoted_member_principal_name};''
                  end
                , N''{role_name}'', r.[name])
                , N''{quoted_role_name}'', quotename(r.[name]))
                , N''{member_principal_name}'', t1.member_principal_name)
                , N''{quoted_member_principal_name}'', quotename(t1.member_principal_name)
               ) as cmd
             , t1.member_principal_name
             , p.[name] as server_principal_name
             , ptso.principal_type_sort_order
             , p.type_desc as principal_type_description
             , r.[name]
             , r.principal_id
             , t1.[sid]
      from     [master].sys.server_principals as p
               inner join (select   dp.[sid]
                                  , cast(dp.[name] as nvarchar(128)) as member_principal_name
                           from     #target_principals as p2
                                    inner join sys.database_principals as dp on p2.principal_id = dp.principal_id
                           where    (dp.[sid] is not null)  
                                    and (is_fixed_role = 0)
                          ) as t1 on p.[sid] = t1.[sid]
               inner join [master].sys.server_role_members as m on m.member_principal_id =  p.principal_id
               inner join [master].sys.server_principals as r on m.role_principal_id = r.principal_id
               outer apply (
                           select case p.[type]
                                   when ''S'' then 1 -- sql user
                                   when ''U'' then 2 -- windows user
                                   when ''G'' then 3 -- windows group
                                   when ''A'' then 4 -- application role
                                   when ''R'' then 5 -- database role
                                   when ''C'' then 6 -- user mapped to a certificate
                                   when ''K'' then 7 -- user mapped to an asymmetric key                                
                                 end as principal_type_sort_order) as ptso
      where    (t1.[sid] <> 0x01) -- don''t want sa/dbo
      order by principal_type_sort_order
             , member_principal_name
             , r.[sid];

      if (@debug = 1) begin

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''showing server role memberships...'', 0, 1) with nowait;

         select   *
         from     #server_memberships as sr
         order by RowID ;

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''getting server permissions...'', 0, 1) with nowait;

      end;

      insert into #server_permissions (
         cmd
       , [object_name]
       , principal_type_sort
       , permission_class
       , permission_class_description
       , major_id
       , minor_id
       , principal_id
       , principal_name
       , principal_type_description
       , permission_type
       , [permission_name]
       , permission_state_description
       , grantor_principal_id
       , grantor_name
      )
      select   replace(replace(replace(replace(
                  N''{perms_state_desc} {permission_name} to {quoted_principal_name}{grant_option};''
                , N''{perms_state_desc}'', case when perms.[state] = N''W'' then N''grant'' else lower(perms.state_desc collate database_default) end)
                , N''{permission_name}'', lower(perms.[permission_name] collate database_default))
                , N''{quoted_principal_name}'', quotename(principals.name))
                , N''{grant_option}'', case when perms.[state] = ''W'' then N'' with grant option'' else N'''' end
               ) as cmd
             , @@SERVERNAME as [object_name]
             , pts.principal_type_sort
             , perms.class as permission_class
             , perms.class_desc as permission_class_description
             , perms.major_id
             , perms.minor_id
             , principals.principal_id
             , principals.name as principal_name
             , principals.type_desc as [principal_type_description]
             , perms.type as permission_type
             , [perms].[permission_name]
             , perms.state_desc as permission_state_description
             , perms.grantor_principal_id
             , grantors.name as grantor_name
      from     [master].sys.server_permissions as perms
               inner join [master].sys.server_principals as principals on perms.grantee_principal_id = principals.principal_id
               inner join (select   dp.[sid]
                                  , dp.[name] as member_principal_name
                           from     #target_principals as p2
                                    inner join sys.database_principals as dp on p2.principal_id = dp.principal_id
                           where    (dp.[sid] is not null)  
                                    and (is_fixed_role = 0)
                          ) as t1 on principals.[sid] = t1.[sid]
               outer apply (select  case principals.[type]
                                      when ''S'' then 1 -- sql user
                                      when ''U'' then 2 -- windows user
                                      when ''G'' then 3 -- windows group
                                      when ''A'' then 4 -- application role
                                      when ''R'' then 5 -- database role
                                      when ''C'' then 6 -- user mapped to a certificate
                                      when ''K'' then 7 -- user mapped to an asymmetric key
                                    end as principal_type_sort
                           ) as pts
               inner join [master].sys.server_principals as grantors on perms.grantor_principal_id = grantors.principal_id
      where    (not ( (perms.class = 100) and (perms.[type] = N''COSQ'' ) ) ) -- don''t want server connect perms: covered by adding logins to server
      order by pts.principal_type_sort
             , principals.name
             , principals.[sid];

      if (@debug = 1) begin

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''showing server permissions...'', 0, 1) with nowait;

         select   *
         from     #server_permissions
         order by RowID;

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''getting database principals...'', 0, 1) with nowait;

      end;

      insert into #database_principals (
         cmd
       , [user_name]
       , principal_id
       , login_name
       , default_schema_name
      )
      select   replace(replace(replace(replace(
                  N''if not exists (select * from sys.database_principals where name = N''''{database_principal_name}'''' and type in (''''S'''', ''''U''''))|   create user {quoted_database_principal_name} for login {quoted_server_principal_name} with default_schema={quoted_default_schema_name};''
                , N''{database_principal_name}'', dp.name)
                , N''{quoted_database_principal_name}'', quotename(dp.name))
                , N''{quoted_server_principal_name}'', quotename(sp.name))
                , N''{quoted_default_schema_name}'', quotename(dp.default_schema_name)
               ) as cmd
             , dp.[name] as [user_name]
             , dp.principal_id
             , sp.name as login_name
             , dp.default_schema_name
      from     #target_principals as p
               inner join sys.database_principals as dp on p.principal_id = dp.principal_id
               left outer join sys.server_principals as sp on dp.[sid] = sp.[sid]
      where    (dp.[type] in (''S'', ''U''))
               and (sp.[name] is not null)
      order by case dp.[type]
                 when ''S'' then 1 -- sql user
                 when ''U'' then 2 -- windows user
                 when ''G'' then 3 -- windows group
                 when ''A'' then 4 -- application role
                 when ''R'' then 5 -- database role
                 when ''C'' then 6 -- user mapped to a certificate
                 when ''K'' then 7 -- user mapped to an asymmetric key
               end
             , dp.[name];

      if (@debug = 1) begin

         raiserror (N'''', 0, 1) with nowait;
         raiserror (N''showing database principals...'', 0, 1) with nowait;

         select   *
         from     #database_principals
         order by RowID;

      end;

   end;

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''getting database roles...'', 0, 1) with nowait;

   end;

   insert into #database_roles (
      cmd
    , role_name
    , principal_id
    , owner_name
   )
   select   replace(replace(replace(
               N''if not exists (select * from sys.database_principals where name = N''''{database_principal_name}'''' and type in (''''A'''', ''''R''''))|   create role {quoted_database_principal_name} authorization {quoted_owner_name};''
             , N''{quoted_owner_name}'', quotename(opn.owner_name))
             , N''{quoted_database_principal_name}'', quotename(dp.[name]))
             , N''{database_principal_name}'', dp.[name]
            ) as cmd
          , dp.[name] as role_name
          , dp.principal_id
          , opn.owner_name
   from     #target_principals as p
            inner join sys.database_principals as dp on p.principal_id = dp.principal_id
            outer apply (
                        select   [name] as owner_name
                        from     sys.database_principals as dp2
                        where    (dp2.principal_id = dp.owning_principal_id)
                        ) as opn
   where    (dp.[type] in (''A'', ''R''))
            and (dp.is_fixed_role = 0)
   order by case dp.[type]
              when ''S'' then 1 -- sql user
              when ''U'' then 2 -- windows user
              when ''G'' then 3 -- windows group
              when ''A'' then 4 -- application role
              when ''R'' then 5 -- database role
              when ''C'' then 6 -- user mapped to a certificate
              when ''K'' then 7 -- user mapped to an asymmetric key
            end
          , dp.[name];

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''showing database roles...'', 0, 1) with nowait;

      select   *
      from     #database_roles
      order by RowID;

   end;

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''getting database role memberships...'', 0, 1) with nowait;

   end;

   insert into #database_memberships (
      cmd
    , member_principal_id
    , member_type_sort_order
    , member_principal_name
    , role_principal_id
    , role_principal_name
    , is_fixed_role
   )
   select   replace(replace(replace(replace(
               case when @recreate_logins = 0 
                  then N''if exists(select * from sys.database_principals where name = ''''{database_principal_name}'''')|   '' 
                  else N'''' 
               end 
             + case when @compatibility_level_prncpl < 110
                  then N''exec sp_addrolemember N''''{role_name}'''', N''''{database_principal_name}''''''
                  else N''alter role {quoted_role_name} add member {quoted_database_principal_name}''
               end 
             + N'';''
             , N''{database_principal_name}'', m.name)
             , N''{role_name}'', r.name)
             , N''{quoted_database_principal_name}'', quotename(m.name))
             , N''{quoted_role_name}'', quotename(r.name)
            ) as cmd
          , m.principal_id as member_principal_id
		    , mts.member_type_sort
          , m.name as member_principal_name
          , r.principal_id role_principal_id
          , r.name as role_principal_name
          , r.is_fixed_role
   from     sys.database_principals as m
            inner join #target_principals as p on m.principal_id = p.principal_id
            inner join sys.database_role_members as rm on m.principal_id = rm.member_principal_id
            inner join sys.database_principals as r on rm.role_principal_id = r.principal_id
            inner join #target_principals as p2 on r.principal_id = p2.principal_id
            outer apply (
                        select   case m.type
			                          when ''S'' then 1 -- sql user
			                          when ''U'' then 2 -- windows user
			                          when ''G'' then 3 -- windows group
			                          when ''A'' then 4 -- application role
			                          when ''R'' then 5 -- database role
			                          when ''C'' then 6 -- user mapped to a certificate
			                          when ''K'' then 7 -- user mapped to an asymmetric key
			                        end as member_type_sort
                        ) as mts
   where		(m.is_fixed_role = 0) 
   order by r.is_fixed_role desc
          , r.name
          , mts.member_type_sort
          , m.name;

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''showing database role memberships...'', 0, 1) with nowait;

      select   *
      from     #database_memberships as dm
      order by RowID;

   end;

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''getting database permissions...'', 0, 1) with nowait;

   end;

   insert into #database_permissions (
      cmd
    , [schema_name]
    , [object_name]
    , column_name
    , principal_type_sort
    , permission_class
    , permission_class_description
    , major_id
    , minor_id
    , principal_id
    , principal_name
    , permission_type
    , principal_type_description
    , [permission_name]
    , permission_state_description
    , grantor_principal_id
    , grantor_name
   )
   select   replace(replace(replace(replace(replace(replace(replace(replace(
               case when @recreate_logins = 0 
                  then N''if exists (select * from sys.database_principals where name = N''''{principal_name}'''')|   ''
                  else N''''
               end 
             + N''{perms_state_desc} {permission_name}{target_prefix}{object} to {quoted_principal_name}{grant_option} as {quoted_grantor_name};''
             , N''{perms_state_desc}'', case when perms.[state] = N''W'' then N''grant'' else lower(perms.state_desc collate database_default) end)
             , N''{permission_name}'', lower(perms.[permission_name] collate database_default))
             , N''{target_prefix}'', case perms.class when 0 then N'''' else N'' on '' end)
             , N''{object}'', replace(replace(replace(
                              case perms.class 
                                 when 0 then N''''
                                 when 3 then N''SCHEMA::{quoted_schema_name}''
                                 when 6 then N''TYPE::{quoted_schema_name}.{quoted_object_name}''
                                 when 16 then N''CONTRACT::{quoted_object_name}''
                                 when 24 then N''SYMMETRIC KEY::{quoted_object_name}''
                                 when 25 then N''CERTIFICATE::{quoted_object_name}''
                                 else N''{quoted_schema_name}.{quoted_object_name}'' + case when labels.column_name is null then N'''' else N'' {quoted_column_name}'' end
                              end 
                            , N''{quoted_schema_name}'', coalesce(quotename(labels.[schema_name] collate database_default), N''''))
                            , N''{quoted_object_name}'', coalesce(quotename(labels.[object_name] collate database_default), N''''))
                            , N''{quoted_column_name}'', coalesce(quotename(labels.[column_name] collate database_default), N'''')
                              )
                           )
             , N''{quoted_principal_name}'', quotename(principals.name))
             , N''{grant_option}'', case when perms.[state] = ''W'' then N'' with grant option'' else N'''' end)
             , N''{quoted_grantor_name}'', quotename(grantors.name))
             , N''{principal_name}'', principals.name
            ) as cmd
          , labels.[schema_name]
          , labels.[object_name]
          , labels.column_name
          , labels.principal_type_sort
          , perms.class
          , perms.class_desc as class_description
          , perms.major_id
          , perms.minor_id
          , principals.principal_id
          , principals.name as [principal_name]
          , perms.[type] as [permission_type]
          , principals.type_desc as [principal_type_description]
          , perms.[permission_name]
          , perms.state_desc as state_description
          , perms.grantor_principal_id
          , grantors.[name] as grantor_name
   from     sys.database_permissions as perms
            inner join sys.database_principals as principals on perms.grantee_principal_id = principals.principal_id
            inner join sys.database_principals as grantors on perms.grantor_principal_id = grantors.principal_id
            inner join #target_principals as p on principals.principal_id = p.principal_id
            outer apply (
                        select   case class
                                    when 1 then object_schema_name(major_id)
                                    when 3 then schema_name(major_id)
                                    when 6 then (select schema_name([schema_id]) from sys.types where user_type_id = perms.major_id)
                                    else null
                                 end as [schema_name]
                               , case class
                                    when 0 then db_name()
                                    when 3 then null -- schema_name(major_id)
                                    when 6 then type_name(major_id)
                                    when 16 then (select [name] from sys.service_contracts where service_contract_id = perms.major_id)
                                    when 24 then (select [name] collate SQL_Latin1_General_CP1_CI_AS from sys.symmetric_keys as sk where sk.symmetric_key_id = perms.major_id)
                                    when 25 then (select [name] collate SQL_Latin1_General_CP1_CI_AS from sys.certificates as c where c.certificate_id = perms.major_id)
                                    else object_name(major_id)
                                 end as [object_name]
                               , case when (perms.minor_id <> 0) and (perms.class = 1) 
                                    then (select [name] from sys.columns where [object_id] = perms.major_id and column_id = perms.minor_id)
                                    else null 
                                 end as column_name
                               , case principals.[type]
			                           when ''S'' then 1 -- sql user
			                           when ''U'' then 2 -- windows user
			                           when ''G'' then 3 -- windows group
			                           when ''A'' then 4 -- application role
			                           when ''R'' then 5 -- database role
			                           when ''C'' then 6 -- user mapped to a certificate
			                           when ''K'' then 7 -- user mapped to an asymmetric key
			                        end as principal_type_sort
                        ) as labels
   where    ((coalesce(labels.[schema_name], '''') <> ''sys'') or (@include_system_objects = 1)) -- don''t want system objects
            and (coalesce(labels.[schema_name], '''') <> ''INFORMATION_SCHEMA'') -- don''t want metadata objects
            and (coalesce(labels.[object_name], '''') not like ''dt_%'') -- don''t want diagram-related objects
            and (coalesce(labels.[object_name], '''') not like ''fn_%'') -- don''t want diagram-related objects
            and (not ( (perms.class = 0) and (perms.[type] = N''CO  '' ) ) ) -- don''t want database connect perms: covered by adding users to database
   order by labels.[schema_name] collate database_default
          , perms.class
          , labels.[object_name] collate database_default
          , labels.column_name collate database_default
          , labels.principal_type_sort
          , principals.name collate database_default
          , perms.state_desc collate database_default
          , perms.permission_name collate database_default;

   if (@debug = 1) begin

      raiserror (N'''', 0, 1) with nowait;
      raiserror (N''showing database permissions...'', 0, 1) with nowait;

      select   *
      from     #database_permissions
      order by RowID;

   end;
   if (@debug = 1) begin
   
      raiserror(N'''', 0, 1) with nowait;
      raiserror(N''generating script...'', 0, 1) with nowait;
      raiserror(N'''', 0, 1) with nowait;

   end;

   print N''-- ============================================='';
   print N''-- The following recreates'' + case when @principal_name is null then N'' all'' else N'' the'' end + N'' principal'' + case when @principal_name is null then N''s'' else N'' '' + quotename(@principal_name) end + N'' in the database '' + quotename(db_name()) + N'' on '' + quotename(@@servername) + N''.''
   print N''--'';
   print N''-- Notes:'';
   print N''--  Role members are'' + case @include_role_members when 1 then N'''' else N'' not'' end + N'' included.'';
   print N''--  System objects are'' + case @include_system_objects when 1 then N'''' else N'' not'' end + N'' included.'';
   print N''--  Logins and users are'' + case @recreate_logins when 1 then N'''' else N'' not'' end + N'' being recreated.'';
   print N''-- ============================================='';
   print N''-- Version History:'';
   print N''-- 1.0:'';
   print N''--  initial production version'';
   print N''-- ============================================='';

   if (exists(select * from #server_principals) or exists(select * from #server_memberships)) begin

      print N''use master;'';
      print N''go'';
      print N'''';

   end;

   declare @rowID_prncpl int
   declare @maxID int;
   declare @cmd_prncpl nvarchar(max);
   declare @crlf_prncpl nvarchar(2);

   set @crlf_prncpl = nchar(13) + nchar(10);

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #server_principals;

   if (@maxID > 0) begin

      print N''-- create logins'';            

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #server_principals
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #server_memberships;

   if (@maxID > 0) begin

      print N''-- add logins to server roles'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #server_memberships
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   select   @rowID_prncpl = min(RowID)
          , @maxID = max(RowID)
   from     #server_permissions;

   if (@maxID > 0) begin

      print N''-- granting server permissions'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #server_permissions
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   print N''set xact_abort, arithabort on;''
   print N''go'';
   print N'''';
   print N''begin transaction;''
   print N''go'';
   print N'''';
   print N''use '' + quotename(db_name()) + N'';'';
   print N''go'';
   print N'''';

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #database_principals;

   if (@maxID > 0) begin

      print N''-- create users for logins'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #database_principals
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #database_roles;

   if (@maxID > 0) begin

      print N''-- create database roles'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #database_roles
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #database_memberships;

   if (@maxID > 0) begin

      print N''-- add users to database roles'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #database_memberships
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   select   @rowID_prncpl = min(RowID), @maxID = max(RowID)
   from     #database_permissions;

   if (@maxID > 0) begin

      print N''-- grant permissions'';

      while (@rowID_prncpl <= @maxID) begin

         select   @cmd_prncpl = replace(cmd, N''|'', @crlf_prncpl)
         from     #database_permissions
         where    (RowID = @rowID_prncpl);
      
         if (nullif(@cmd_prncpl, N'''') is not null) begin
         
            print @cmd_prncpl;  
            print N''go'';
            print N'''';

         end;

         set @rowID_prncpl = @rowID_prncpl + 1;

      end;

   end;

   print N''if (@@trancount > 0) begin'';
   print N''   commit transaction;'';
   print N''end else begin'';
   print N''   print N''''Principal recreation failed!'''';''; 
   print N''end;'';
   print N'''';';

   exec ( @useCmd );

   raiserror(N'',0,1) WITH NOWAIT;
end;

select   *
from     @dbFiles
order by database_name 
       , rowID;

PRINT N'';
PRINT N'--Print elapsed time';
PRINT N'';
PRINT N'DECLARE @startTime DATETIME;';
PRINT N'SELECT TOP 1 @startTime = timestamps FROM #elapsedTimeAndFilePath;';
PRINT N'';
PRINT N'PRINT N''Total Elapsed Time: '' +  STUFF(CONVERT(NVARCHAR(12), CURRENT_TIMESTAMP - @startTime, 14), 9, 1, ''.''); --hh:mi:ss.mmm';
PRINT N'';
PRINT N'PRINT N'''';';
PRINT N'PRINT N''*****Recreation of databases on '' + quotename(@@SERVERNAME) + N'' complete. Continue to Secondary Logshipping*****'';';
PRINT N'';
PRINT N'DROP TABLE #elapsedTimeAndFilePath';
