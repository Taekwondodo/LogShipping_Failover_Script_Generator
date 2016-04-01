/*
 * Generate a script to re-create databases on a server
 * 
 * Params:
 *  - @databaseName = Specifies the name of a single database, or, if null, to list all user databases present
 */
use [master];
go

declare @databaseName sysname;

--set @databaseName = N'i2b2demodata';
--set @databaseName = N'i2b2hive';
--set @databaseName = N'i2b2imdata';
--set @databaseName = N'i2b2metadata';
--set @databaseName = N'i2b2pm';
--set @databaseName = N'i2b2workdata';

--set @databaseName = N'PerformanceTest';
--set @databaseName = N'Messaging';
--set @databaseName = 'PBRCConfiguration';
--set @databaseName = N'Merge';
--set @databaseName = N'Footprints';
--set @databaseName = N'LACaTS';
--set @databaseName = N'PedalDesk';
--set @databaseName = null; -- N'tempdb'; -- 
--set @databaseName = N'Security';

--set @databaseName = N'DBA';

set @databaseName = N'Footprints';

--================================================================
set nocount on;

declare @dbNames table (
   rowId int not null identity(1, 1)
 , name sysname not null primary key
 , owner_name sysname null
 , [compatibility_level] tinyint                -- 70; 80; 90; 100; 110; 120
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

declare @dbFiles table (
   database_name     sysname
 , data_space_name   sysname null
 , file_type         tinyint
 , file_type_desc    nvarchar(60)
 , data_file_name    sysname
 , physical_name     nvarchar(260)
 , size              int
 , max_size          int
 , is_percent_growth bit
 , growth            int
 , is_default        bit
 , rowId             int
 , fileGroupRowID    int
 , filespec          as (case
                           when file_type in (0, 1)
                              then N'( name = N''' + data_file_name + N''''
                                 + N', filename = N''' + physical_name + N''''
                                 + N', size = ' + cast((size * cast(8 as bigint) / case when size >= 268435456 then 1048576 else 1 end) as nvarchar(40))
                                 + case when size > 268435456 then N'GB' else N'KB' end
                                 + N', maxsize = ' 
                                 + case when max_size = -1 then N'unlimited' else 
                                    cast((max_size * cast(8 as bigint)
                                       / case when max_size >= 268435456 then 1048576 else 1 end) as nvarchar(40))
                                    + case when max_size >= 268435456 then N'GB' else N'KB' end
                                 end
                                 + N', filegrowth = ' 
                                 + case when is_percent_growth = 1 then cast(growth as nvarchar(3)) + N'%' else 
                                    cast((growth * cast(8 as bigint) / case when growth >= 268435456 then 1048576 else 1 end) as nvarchar(40))
                                    + case when growth >= 268435456 then N'GB' else N'KB' end
                                 end
                                 + N' )'
                           else N''
                        end)
);

declare @tab nchar(3);
declare @crlf nchar(2);
declare @dbName sysname
 , @compatibility_level tinyint                 -- 70; 80; 90; 100; 110; 120
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

set @databaseName = nullif(@databaseName, N'');
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
from     sys.databases as d
         left outer join sys.server_principals as sp on d.owner_sid = sp.sid
where    ((d.name not in (N'master', N'model', N'msdb', N'tempdb'))
          and (@databaseName is null)
         )
         or (d.name = @databaseName)
order by d.name;

select   *
from     @dbNames as dn
order by name;

declare @tmpstr nvarchar(max);

print N'/*';
print N' * Server Databases Script ';

set @tmpstr = N' * For ';

if (@databaseName is null) 
   set @tmpstr = @tmpstr + N'all user databases';
else 
   set @tmpstr = @tmpstr + N'''' + @databaseName + N'''';

set @tmpstr = @tmpstr + N' on ' + @@servername;

print @tmpstr;

set @tmpstr = N' * Generated ' + convert(varchar, getdate()) + N' by ' + suser_sname();

print @tmpstr;

print ' *';

if (not exists(select * from @dbNames)) begin

   print N' * ! No ' + case when @databaseName is null then N'user databases' else N'database called ' + quotename(@dbName) end + N' found!';
   print N' *';

end else if (@databaseName is null) begin   
		
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

set @dbName = N'';

declare @dbRowId int;

while (exists(select * from @dbNames where (name > @dbName))) begin

   select   top 1
            @dbRowId = dn.rowId
          , @dbName = name
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
--where    (df.[type] <> 4) -- ignore fulltext
order by case when ds.name = N''PRIMARY'' then 1 else 2 end
       , df.[type]
       , df.[file_id];'
       , N'{database_name}', @dbName)
       , N'{quoted_database_name}', quotename(@dbName));

   insert into @dbFiles
      (database_name, data_space_name, file_type, file_type_desc, data_file_name, physical_name, size, max_size, is_percent_growth, growth, is_default, rowID, fileGroupRowID) 
   exec ( @cmd );

   print N'use [master];';
   print N'go';
   print N'';

   print N'print N''Begin Database: ' + quotename(@dbName) + N''';';
   print N'go';
   print N'';

   print N'print N''creating database ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'create database ' + quotename(@dbName) + N' on';
   
   set @rowID = 0;
   set @new_file_group = 1;
   set @data_space_name = N'';
   
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

   print N'go';
   print N'print N''setting compatibility level for ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'exec dbo.sp_dbcmptlevel @dbname=N''' + @dbName + N''', @new_cmptlevel=' + cast(@compatibility_level as nvarchar(3)) + N';';
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

   if (@owner_name is not null) begin

      print N'print N''setting database owner for ' + quotename(@dbName) + N'...'';';  
      print N'if (exists(select * from [master].sys.server_principals where name = N''' + @owner_name + N''')) begin'
      print @tab + N'alter authorization on database::' + quotename(@dbName) + N' to ' + quotename(@owner_name) + N';';
      print N'end else begin';
      print @tab + N'raiserror (N''Unable to find login ' + quotename(@owner_name) + N' to set owner of database ' + quotename(@dbName) + N'!'', 16, ' + cast(@dbRowId as nvarchar(10)) + N');';
      print N'end;';
      print N'go';
  
   end; 
   
   print N'use ' + quotename(@dbName) + ';';
   print N'go';
   print N'print N''setting full text state for ' + quotename(@dbName) + N'...'';';
   print N'go';
   print N'if (fulltextserviceproperty(N''IsFullTextInstalled'') = 1) begin';
   print @tab + N'exec ' + quotename(@dbName) + '.dbo.sp_fulltext_database @action=''' + case when @is_fulltext_enabled = 1 then N'enable' else N'disable' end + N''';';

   if exists(select * from @dbFiles as df where (df.database_name = @dbName) and (df.file_type = 4)) begin

      set @rowID = 0;
      set @filespec = N'';

      while exists(select * from @dbFiles as df where (df.database_name = @dbName) and (file_type = 4) and (df.rowID > @rowID)) begin

         select top 1
            @rowID = df.rowID
          , @filespec = @tab + 'create fulltext catalog [' +  df.data_file_name + '] in path ''' + df.physical_name + ''' authorization [dbo];'

         from
            @dbFiles as df
         where
            (df.database_name = @dbName)
            and (df.file_type = 4)
            and (df.rowID > @rowID)
         order by
            df.rowID;

         print N'';
         print @filespec;

      end;
   
      print N'';
      
   end;

   print N'end;';
   print N'go';

   print N'print N''End Database: ' + quotename(@dbName) + N''';';
   print N'go';
   print N'';

end;

select   *
from     @dbFiles
order by database_name 
       , rowID;

