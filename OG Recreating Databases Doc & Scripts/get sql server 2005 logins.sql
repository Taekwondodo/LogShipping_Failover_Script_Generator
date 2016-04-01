/*
 * Generate a script to re-create logins on a SQL Server 2000, 2005, 2008, 2008 R2
 * 
 * Params:
 *  - @login_name      = Specifies the name of a single login, or, if null, to list all logins present
 *  - @include_db      = Specifies whether or not to include the default database for the logins
 *  - @include_role    = Specifies whether or not to include system roles for the logins
 *  - @include_sqlAuth = Specifies whether or not to include logins authenticated by SQL Server directly, ignored if @login_name is specified
 *  - @include_winAuth = Specifies whether or not to include logins authenticated by Windows, ignored if @login_name is specified
 */

use master;
go

declare @login_name      sysname
      , @include_db      bit
      , @include_role    bit
      , @debug           bit
      , @include_sqlAuth bit
      , @include_winAuth bit;

set @include_db = 1;
set @include_role = 1;
set @debug = 1;

set @include_sqlAuth = 1;
set @include_winAuth = 1;

--set @login_name = N'pbrc\loriodj';

--set @login_name = N'LinkUser';

--set @login_name = N'i2b2demodata';
--set @login_name = N'i2b2hive';
--set @login_name = N'i2b2imdata';
--set @login_name = N'i2b2metadata';
--set @login_name = N'i2b2pm';
--set @login_name = N'i2b2workdata';

--set @login_name = N'tsgUser';

--set @login_name = N'WebApplication';
--set @login_name = N'SMSUser';
--set @login_name = N'FPLookup';
--set @login_name = N'ServerStatsUser';
--set @login_name = N'LACaTSUser';
--set @login_name = N'PedalUser';
--set @login_name = N'MergeImportUser';
--set @login_name = N'PBRC\DavenpFG';
--set @login_name = N'PALReader';
--set @login_name = N'PBRC\PhamQ';
--set @login_name = N'PBRC\secLeblanEA';
--set @login_name = N'PBRC\LorioDJ';
--set @login_name = N'PBRC\App_Unity';
--set @login_name = N'BusinessDatesServiceUser';
--set @login_name = N'WellnessUser'; -- null; -- 
--set @login_name = N'CBCSyncUser';
--set @login_name = N'ArmyUser';
--set @login_name = N'pbrc\allenhr';
--set @login_name = N'pbrc\davenpfg';
--set @login_name = N'pbrc\acharyav';
--set @login_name = N'PedalUser';

--------------------------------------------

select
   @login_name = nullif(@login_name, N'')
 , @include_db = coalesce(@include_db, 0)
 , @include_role = coalesce(@include_role, 0)
 , @debug = coalesce(@debug, 0)
 , @include_sqlAuth = coalesce(@include_sqlAuth, 0)
 , @include_winAuth = coalesce(@include_winAuth, 0);

set nocount on;

declare @version_string varchar(256);

set @version_string = cast(serverproperty(N'productversion') as varchar(256));

declare @major_version int;

set @major_version = left(@version_string, charindex(N'.', @version_string) - 1);

if (@major_version < 9) begin

   raiserror (N'-- %s is not recent enough!  Looking for stored procedure alternative...', 0, 1, @@servername);

   if exists (
         select
            *
         from
            dbo.sysobjects
         where
            id = object_id(N'[dbo].[sp_help_revlogin_2000_to_2005]')
            and objectproperty(id, N'IsProcedure') = 1
      ) begin

      exec [sp_help_revlogin_2000_to_2005]
         @login_name
       , @include_db
       , @include_role;

   end else begin

      raiserror (N'-- First alternate stored procedure not found!  Looking for 2nd alternate stored procedure...', 0, 1, @@servername);

      if exists (
            select
               *
            from
               dbo.sysobjects
            where
               id = object_id(N'[dbo].[sp_help_revlogin]')
               and objectproperty(id, N'IsProcedure') = 1
         ) begin

         exec [sp_help_revlogin]
            @login_name
          , @include_db
          , @include_role;

      end else begin

         raiserror (N'-- No alternative stored procedures found!  Aborting...', 0, 1);

      end;

   end;

end else begin

   declare @name          sysname
         , @xstatus       int
         , @binpwd        varbinary(256)
         , @dfltdb        nvarchar(256)
         , @txtpwd        nvarchar(512)
         , @tmpstr        nvarchar(4000)
         , @SID_varbinary varbinary(85)
         , @SID_string    nvarchar(512)
         , @isntname      int
         , @sysadmin      int
         , @securityadmin int
         , @serveradmin   int
         , @setupadmin    int
         , @processadmin  int
         , @diskadmin     int
         , @dbcreator     int
         , @bulkadmin     int;

   declare @logins table (
      RowID         int            not null identity (1, 1)
    , [sid]         varbinary(85)
    , [status]      smallint
    , [name]        sysname
    , dbname        sysname
    , [password]    varbinary(256) null
    , isntname      int            null
    , sysadmin      int            null
    , securityadmin int            null
    , serveradmin   int            null
    , setupadmin    int            null
    , processadmin  int            null
    , diskadmin     int            null
    , dbcreator     int            null
    , bulkadmin     int            null
    , createdate    datetime       null
    , updatedate    datetime       null
   );

   declare @rowid    int
         , @maxrowid int;

   if (@login_name is null) begin

      insert into @logins (
         [sid]
       , [status]
       , [name]
       , dbname
       , [password]
       , isntname
       , sysadmin
       , securityadmin
       , serveradmin
       , setupadmin
       , processadmin
       , diskadmin
       , dbcreator
       , bulkadmin
       , createdate
       , updatedate
      )
      select
         l1.[sid]
       , l1.[status]
       , l1.[name]
       , l1.dbname
       , l2.password_hash as [password]
       , l1.isntname
       , l1.sysadmin
       , l1.securityadmin
       , l1.serveradmin
       , l1.setupadmin
       , l1.processadmin
       , l1.diskadmin
       , l1.dbcreator
       , l1.bulkadmin
       , l1.createdate
       , l1.updatedate
      from
         sys.syslogins l1
         left outer join sys.sql_logins l2
            on l1.sid = l2.sid
      where
         (l1.[name] <> N'sa')
         and (l1.[name] not like N'NT AUTHORITY\%')
         and (l1.[name] not like N'BUILTIN\%')
         and (l1.[name] not like 'NT SERVICE\%')
         and (l1.[name] not like N'#%')
         and (l1.denylogin = 0)
         and ((l1.isntname = @include_winAuth) -- if including windows logins, [isntname] must be 1 (same as parameter)
         or (l1.isntname <> @include_sqlAuth)) -- if including sql logins, [isntname] must be 0 (opposite of parameter)
      order by
         l1.[name];

   end else begin

      insert into @logins (
         [sid]
       , [status]
       , [name]
       , dbname
       , [password]
       , isntname
       , sysadmin
       , securityadmin
       , serveradmin
       , setupadmin
       , processadmin
       , diskadmin
       , dbcreator
       , bulkadmin
       , createdate
       , updatedate
      )
      select
         l1.[sid]
       , l1.[status]
       , l1.[name]
       , l1.dbname
       , l2.password_hash as [password]
       , l1.isntname
       , l1.sysadmin
       , l1.securityadmin
       , l1.serveradmin
       , l1.setupadmin
       , l1.processadmin
       , l1.diskadmin
       , l1.dbcreator
       , l1.bulkadmin
       , l1.createdate
       , l1.updatedate
      from
         sys.syslogins l1
         left outer join sys.sql_logins l2
            on l1.sid = l2.sid
      where
         (l1.[name] = @login_name)
         and (l1.denylogin = 0);

   end;

   if (@debug = 1) begin

      select
         *
      from
         @logins as l
      order by
         l.name;

   end;

   print N'/*';
   print N' * Server Logins Script ';

   set @tmpstr = N' * For ';

   if (@login_name is null) 
      set @tmpstr = @tmpstr + 
            case
            when (@include_sqlAuth = 1)
               and (@include_winAuth = 1)
               then N'all logins'
            when @include_winAuth = 1
               then N'Windows logins'
            else N'SQL logins'
         end; 
   else 
      set @tmpstr = @tmpstr + N'''' + @login_name + N'''';

   set @tmpstr = @tmpstr + N' on ' + @@servername;

   if (@include_db = 1) set @tmpstr = @tmpstr + N', including default database';

   if (@include_role = 1) set @tmpstr = @tmpstr + N', including system roles';

   print @tmpstr;

   set @tmpstr = N' * Generated ' + convert(varchar, getdate());

   print @tmpstr;

   print ' *';

   if (not exists (
         select
            *
         from
            @logins
      )) begin

      if (@login_name is null) set @tmpstr = N' * ! No logins found !'; else set @tmpstr = N' * ! No login found !';

      print @tmpstr;

      print N' *';
      print N' */';

   end else begin

      print N' * Logins created by this script:';

      select
         @rowid = 1
       , @maxrowid = max(RowID)
      from
         @logins;

      while (@rowid <= @maxrowid) begin

         select
            @name = [name]
         from
            @logins
         where
            (RowID = @rowid);

         set @tmpstr = ' * ' + char(9) + @name;
         print @tmpstr;

         set @rowid = @rowid + 1;

      end;

      print N' */';

      set @rowid = 1;

      while (@rowid <= @maxrowid) begin

         select
            @SID_varbinary = [sid]
          , @name = [name]
          , @binpwd = [password]
          , @isntname = isntname
          , @dfltdb = dbname
          , @sysadmin = sysadmin
          , @securityadmin = securityadmin
          , @serveradmin = serveradmin
          , @setupadmin = setupadmin
          , @processadmin = processadmin
          , @diskadmin = diskadmin
          , @dbcreator = dbcreator
          , @bulkadmin = bulkadmin
         from
            @logins
         where
            (RowID = @rowid);

         print N'';
         set @tmpstr = 'print N''Begin Login: ' + @name + N''';';
         print @tmpstr;

         print N'print N''creating login for user...'';';
         print N'go';

         -- NT authenticated account/group 
         set @tmpstr = N'if not exists (select * from sys.server_principals where [name] = N''' + @name + N''')';
         print @tmpstr;

         if (@isntname = 1) begin

            set @tmpstr = char(9) + N'create login ' + quotename(@name) + N' from windows';

         end else begin

            declare @x xml;

            set @x = N'<root></root>';

            -- SQL Server authentication 
            set @SID_string = N'0x' + @x.value(N'xs:hexBinary(sql:variable("@sid_varbinary"))', N'[nvarchar](512)');

            if (@binpwd is not null) begin

               set @txtpwd = N'0x' + @x.value(N'xs:hexBinary(sql:variable("@binpwd"))', N'[nvarchar](512)');

               -- Non-null password 
               set @tmpstr = char(9) + N'create login ' + quotename(@name) + N' with password=' + @txtpwd + N' hashed';

            end else begin

               -- Null password 
               set @tmpstr = char(9) + N'create login ' + quotename(@name) + N' with password=''''';

            end;

            set @tmpstr = @tmpstr + ', check_policy=off, sid=' + @SID_string;

         end;

         if (@include_db = 1) begin

            if (@isntname = 1) set @tmpstr = @tmpstr + N' with ' else set @tmpstr = @tmpstr + N', ';

            set @tmpstr = @tmpstr + N'default_database=' + quotename(@dfltdb);

         end;

         print @tmpstr + N';';
         print N'go'

         if (@include_role = 1)
            and ((@sysadmin = 1)
               or (@securityadmin = 1)
               or (@serveradmin = 1)
               or (@setupadmin = 1)
               or (@processadmin = 1)
               or (@diskadmin = 1)
               or (@dbcreator = 1)
               or (@bulkadmin = 1)
            ) begin

            print N'';
            print N'print N''setting system roles for user...'';';

            if (@sysadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''sysadmin'';';
               print @tmpstr;

            end;

            if (@securityadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''securityadmin'';';
               print @tmpstr;

            end;

            if (@serveradmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''serveradmin'';';
               print @tmpstr;

            end;

            if (@setupadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''setupadmin'';';
               print @tmpstr;

            end;

            if (@processadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''processadmin'';';
               print @tmpstr;

            end;

            if (@diskadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''diskadmin'';';
               print @tmpstr;

            end;

            if (@dbcreator = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''dbcreator'';';
               print @tmpstr;

            end;

            if (@bulkadmin = 1) begin

               set @tmpstr = N'exec master.dbo.sp_addsrvrolemember @loginame=N''' + @name + N''', @rolename=N''bulkadmin'';';
               print @tmpstr;

            end

            print 'go';

         end;

         set @tmpstr = N'print N''End Login: ' + @name + N''';';
         print @tmpstr;
         print N'go';

         set @rowid = @rowid + 1;

      end;

   end;

end;