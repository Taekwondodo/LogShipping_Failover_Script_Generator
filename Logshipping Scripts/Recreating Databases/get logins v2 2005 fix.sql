/*
 * Generate a script to re-create logins on a server with SQL 2005 or higher
 * 
 * Params:
 *  - @filter_principal_name       = Specifies the name of a single server principal, or, if null, to list all server principals present
 *  - @include_db                  = Specifies whether or not to include the default database for the server principals
 *  - @include_lang                = Specifies whether or not to include the default language for the server principals
 *  - @include_role                = Specifies whether or not to include server roles for the server principals
 *  - @@include_sqlAuthPrincipals  = Specifies whether or not to include server principals authenticated by SQL Server directly, ignored if @filter_principal_name is specified
 *  - @@include_winAuthPrincipals  = Specifies whether or not to include server principals authenticated by Windows (including groups), ignored if @filter_principal_name is specified
 *  - @include_mappedPrincipals    = Specifies whether or not to include mapped logins, ignored if @filter_principal_name is specified
 */

use master;

go

declare @filter_principal_name     sysname
      , @include_db                bit
      , @include_lang              bit
      , @include_role              bit
      , @debug                     bit
      , @include_sqlAuthPrincipals bit
      , @include_winAuthPrincipals bit
      , @include_mappedPrincipals  bit;

set @include_db = 1;
set @include_lang = 1;
set @include_role = 1;
set @debug = 1;

set @include_sqlAuthPrincipals = 1;
set @include_winAuthPrincipals = 1;
set @include_mappedPrincipals = 0;

--set @filter_principal_name = N'pbrc\loriodj';

--set @filter_principal_name = N'guest';

--set @filter_principal_name = N'WebApplication';
--set @filter_principal_name = N'##MS_PolicyEventProcessingLogin##';
--set @filter_principal_name = N'PBRC\AlexanDE';
--set @filter_principal_name = N'PBRC\SQL Server RCG Package Admin';

--------------------------------------------

select
   @filter_principal_name = nullif(@filter_principal_name, N'')
 , @include_db = coalesce(@include_db, 1)
 , @include_lang = coalesce(@include_lang, 1)
 , @include_role = coalesce(@include_role, 1)
 , @debug = coalesce(@debug, 0)
 , @include_sqlAuthPrincipals = coalesce(@include_sqlAuthPrincipals, 1)
 , @include_winAuthPrincipals = coalesce(@include_winAuthPrincipals, 1)
 , @include_mappedPrincipals = coalesce(@include_mappedPrincipals, 1);

if (@filter_principal_name is not null) begin

   set @include_sqlAuthPrincipals = 1;
   set @include_winAuthPrincipals = 1;
   set @include_mappedPrincipals = 1;

end;

if (@debug = 1) begin

   select
      @filter_principal_name     as FilterPrincipalName
    , @include_db                as IncludeDefaultDatabase
    , @include_lang              as IncludeDefaultLanguage
    , @include_role              as IncludeServerRoles
    , @include_sqlAuthPrincipals as IncludeSqlAuthenticatedPrincipals
    , @include_winAuthPrincipals as IncludeWinAuthenticatedPrincipals
    , @include_mappedPrincipals  as IncludeMappedPrincipals;

end;

set nocount on;

declare @principals table (
   name                  sysname        not null primary key
 , principal_id          int
 , [sid]                 varbinary(85)
 , type_desc             nvarchar(60)   not null
 , is_disabled           bit
 , create_date           datetime
 , modify_date           datetime
 , default_database_name sysname        null
 , default_language_name sysname        null
 , credential_id         int
 , owning_principal_id   int
 , is_fixed_role         bit
 , password_hash         varbinary(256) null
 , is_policy_checked     bit
 , is_expiration_checked bit
);

  /*
  ==========================================================
  First version check
  The purpose of the following 2 try..catch statements is to direct the flow of the script based on whether or not the sql server version of the server supports user-defined server roles (sql server 2012 & later)
  The dynamic sql assumes the server does, and if the server doesn't sp_executesql will return with an error that will be caught by the try, and the script will be directed to the sql server 2008 & earlier friendly code within the catch
 
  Initial insert into @principals. Principals are filtered based on if we want sql, windows, or mapped principals
  We don't want any principals that are fixed roles or server roles (along with the rest of the conditionals in the where statement obvs)
  ==========================================================
  */

declare @cmd nvarchar(max)
       ,@params nvarchar(500);

set @cmd = 'select
   sp.name
   , sp.principal_id
   , sp.[sid]
   , sp.type_desc
   , sp.is_disabled
   , sp.create_date
   , sp.modify_date
   , sp.default_database_name
   , sp.default_language_name
   , sp.credential_id
   , sp.owning_principal_id
   , sp.is_fixed_role
   , sl.password_hash
   , sl.is_policy_checked
   , sl.is_expiration_checked
from
   sys.server_principals as sp
   left outer join sys.sql_logins as sl 
      on sp.[sid] = sl.[sid]
where
   (sp.name <> N''sa'')
   and (sp.[name] not like N''NT AUTHORITY\%'')
   and (sp.[name] not like N''BUILTIN\%'')
   and (sp.[name] not like ''NT SERVICE\%'')
   and (sp.[name] not like N''#%'')
   and (sp.is_fixed_role = 0)
   and (sp.type_desc <> N''SERVER_ROLE'')
   and ((sp.type_desc <> N''SQL_LOGIN'') or (@include_sqlAuthPrincipals = 1))
   and ((sp.type_desc not like N''WINDOWS_%'') or (@include_winAuthPrincipals = 1))
   and ((sp.type_desc not like N''%_MAPPED_LOGIN'') or (@include_mappedPrincipals = 1))
   and ((nullif(@filter_principal_name, N'''') is null) or (sp.name = @filter_principal_name))
order by
   sp.name;'

set @params = N'@filter_principal_name     sysname
               , @include_sqlAuthPrincipals bit
               , @include_winAuthPrincipals bit
               , @include_mappedPrincipals  bit';

begin try

   -- Execute the sql server 2012 & later code

   insert into @principals (
      name
    , principal_id
    , [sid]
    , type_desc
    , is_disabled
    , create_date
    , modify_date
    , default_database_name
    , default_language_name
    , credential_id
    , owning_principal_id
    , is_fixed_role
    , password_hash
    , is_policy_checked
    , is_expiration_checked
   )

   exec sp_executesql @cmd, @params, 
                            @filter_principal_name = @filter_principal_name
                           ,@include_sqlAuthPrincipals = @include_sqlAuthPrincipals
                           ,@include_winAuthPrincipals = @include_winAuthPrincipals
                           ,@include_mappedPrincipals = @include_mappedPrincipals;

end try
begin catch

   SELECT ERROR_MESSAGE() AS version_check_1_ErrorMessage

   -- Execute sql server 2008 & ealier friendly code

   insert into @principals (
         name
       , principal_id
       , [sid]
       , type_desc
       , is_disabled
       , create_date
       , modify_date
       , default_database_name
       , default_language_name
       , credential_id
       , sp.is_fixed_role
       , password_hash
       , is_policy_checked
       , is_expiration_checked
      )
      select
         sp.name
       , sp.principal_id
       , sp.[sid]
       , sp.type_desc
       , sp.is_disabled
       , sp.create_date
       , sp.modify_date
       , sp.default_database_name
       , sp.default_language_name
       , sp.credential_id
       , 0                        -- 0 is hard coded here since principals that aren't server roles can't be fixed in sql server 2008 & ealier
       , sl.password_hash
       , sl.is_policy_checked
       , sl.is_expiration_checked
      from
         sys.server_principals as sp
         left outer join sys.sql_logins as sl 
            on sp.[sid] = sl.[sid]
      where
         (sp.name <> N'sa')
         and (sp.[name] not like N'NT AUTHORITY\%')
         and (sp.[name] not like N'BUILTIN\%')
         and (sp.[name] not like 'NT SERVICE\%')
         and (sp.[name] not like N'#%')
         and (sp.type_desc <> N'SERVER_ROLE')
         and ((sp.type_desc <> N'SQL_LOGIN') or (@include_sqlAuthPrincipals = 1))
         and ((sp.type_desc not like N'WINDOWS_%') or (@include_winAuthPrincipals = 1))
         and ((sp.type_desc not like N'%_MAPPED_LOGIN') or (@include_mappedPrincipals = 1))
         and ((nullif(@filter_principal_name, N'') is null) or (sp.name = @filter_principal_name))
      order by
         sp.name;

end catch;


-- We use @membership to hold the roles that our principals in @principal have 

declare @memberships table (
   role_principal_id   int
 , member_principal_id int
);

insert into @memberships (
   role_principal_id
 , member_principal_id
)
select
   srm.role_principal_id
 , srm.member_principal_id
from
   sys.server_role_members as srm
   inner join @principals as p
      on srm.member_principal_id = p.principal_id;


-- #temp is a temporary table instead of a table variable so it can be accessed within the dynamic sql involved in the 2nd insert to @principals

IF OBJECT_ID('tempdb.dbo.#temp', 'U') IS NOT NULL
    DROP TABLE #temp;
CREATE TABLE #temp (principal_id int);

-- It appears that we're using #temp to hold the principals of the roles that our principals in @principals have, but aren't present within @principals themselves
-- For example if a @principal principal is a sysadmin, it will be included here (as we filtered against such principals (server role & fixed) in the initial @principals insert above) 

insert into #temp (
   principal_id
)
select
   m.role_principal_id
from
   @memberships as m
except
select
   p.principal_id
from
   @principals as p;


-- Here we're adding the server role principals present in #temp to @principals

while (exists(select * from #temp as t)) begin
  
  --==========================================================
  -- Second version check
  --==========================================================

  set @cmd = 'select
          sp.name
        , sp.principal_id
        , sp.[sid]
        , sp.type_desc
        , sp.is_disabled
        , sp.create_date
        , sp.modify_date
        , sp.default_database_name
        , sp.default_language_name
        , sp.credential_id
        , sp.owning_principal_id
        , sp.is_fixed_role
      from
         sys.server_principals as sp
         inner join #temp as t
            on sp.principal_id = t.principal_id;'

  begin try
   
      --Execute the sql server 2012 & later code
      
      insert into @principals (
         name
       , principal_id
       , [sid]
       , type_desc
       , is_disabled
       , create_date
       , modify_date
       , default_database_name
       , default_language_name
       , credential_id
       , owning_principal_id
       , is_fixed_role
      )
     
      exec sp_executesql @cmd;

   end try
   begin catch

      select ERROR_MESSAGE() AS version_check_2_ErrorMessage

      -- Execute sql server 2008 & ealier friendly code

      insert into @principals (
         name
         , principal_id
         , [sid]
         , type_desc
         , is_disabled
         , create_date
         , modify_date
         , default_database_name
         , default_language_name
         , credential_id
         , is_fixed_role
      )
      select
           sp.name
         , sp.principal_id
         , sp.[sid]
         , sp.type_desc
         , sp.is_disabled
         , sp.create_date
         , sp.modify_date
         , sp.default_database_name
         , sp.default_language_name
         , sp.credential_id
         , 1                        -- 1 is hard coded here since server roles in sql server 2008 & earlier have to be fixed
      from
         sys.server_principals as sp
         inner join #temp as t
            on sp.principal_id = t.principal_id;

   end catch;

   /*
   We delete and then insert into #temp again in order to include user-defined server roles that are members of other server roles (nested membership).
   Example:

   @principals holds one principal with id = 100;
   Say we have the following within [sys.server_role_members]:

   role_id | member_id
   ---------------
   1       | 100
   ---------------
   2       | 1

   When we join this to @principals as we're populating @memberships, @memberships will only have the tupe 1|100 inserted into it as it is the only tuple that has a member_id that exists within @principals
   Next we take all of the role_id's within @memberships that don't exist within @principals and insert them into #temp. In this case 1.
   Now we want @principals to hold the role_id of every principal within it that occupies one as they're going to be relevant when recreating this principals, so we insert the server role principal 1 within #temp into @principals
   But what about the server role with an id of 2? 1 is now a principal within @principals but wasn't included. The solution is what we're doing below. 
   Essentially we're just redoing the entire loop with the new @principals that now includes server role principal 1 so that we can include the nested server roles that we filtered out before.

   */

   insert into @memberships (
      role_principal_id
    , member_principal_id
   )
   select
      srm.role_principal_id
    , srm.member_principal_id -- New members are now the server role principals that were just inserted into @principals
   from
      sys.server_role_members as srm
      inner join @principals as p
         on srm.member_principal_id = p.principal_id
      inner join #temp as t
         on srm.member_principal_id = t.principal_id;

   delete from #temp;
      
   insert into #temp (
      principal_id
   )
   select
      m.role_principal_id
   from
      @memberships as m
   except
   select
      p.principal_id
   from
      @principals as p;

end;

if @debug = 1 begin

   select
      *
   from
      @principals as p
   order by
      p.name;

end;

if @debug = 1 begin

   select
      *
   from
      @memberships as m
   order by
      m.member_principal_id
    , m.role_principal_id;

end;



--=============================================================================
-- *
-- * Begin outputting the script
-- *
--=============================================================================


declare @tmpstr nvarchar(4000);

print N'/*';
print N' * Server Principals Script ';

set @tmpstr = N'';

if (@filter_principal_name is null) begin

   if (@include_sqlAuthPrincipals = 1) and (@include_winAuthPrincipals  = 1) and (@include_mappedPrincipals = 1) begin
      set @tmpstr = N'';
   end else begin
      if (@include_sqlAuthPrincipals = 1) set @tmpstr = N' SQL Authenticated';
      if (@include_winAuthPrincipals = 1) set @tmpstr = @tmpstr + case when @tmpstr = N'' then N'' else N' and' end + N' Windows Authenticated';
      if (@include_mappedPrincipals = 1) set @tmpstr = @tmpstr + case when @tmpstr = N'' then N'' else N' and' end + N' Mapped Login'
   end;

   set @tmpstr = N'all' + @tmpstr + N' principals'

end else begin

   set @tmpstr = @tmpstr + quotename(@filter_principal_name);

end;

set @tmpstr = N' * For ' + @tmpstr + N' on ' + @@servername;

print @tmpstr;

if (@include_db = 1) or (@include_lang = 1) or (@include_role = 1) begin

   set @tmpstr = null;

   if (@include_db = 1) set @tmpstr = coalesce(@tmpstr + N'', N'') + N'default database';

   if (@include_lang = 1) set @tmpstr = coalesce(@tmpstr + case when @include_role = 1 then N', ' else N' and ' end, N'') + N'default language';

   if (@include_role = 1) set @tmpstr = coalesce(@tmpstr + N' and ', N'') + N'server roles';

   print N' * Including ' + @tmpstr;

end;

set @tmpstr = N' * Generated ' + convert(varchar, getdate());

print @tmpstr;

print N' * ';
print N' * Server privileges are not recreated by this script!';

declare @name      sysname
      , @role_name sysname;

--
-- Fixed roles are present by default in every database. As such they don't need to be recreated, which is why we're not mentioning any of the fixed principals w/in @principals here
--

-- Output the recreated server roles

if exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc = N'SERVER_ROLE')) begin 

   print N' * ';
   print N' * Server roles recreated by this script:';
   print N' * ';

   set @role_name = N'';

   while (exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc = N'SERVER_ROLE') and (p.name > @role_name))) begin

      select top 1
         @role_name = p.name
      from
         @principals as p
      where
         (p.is_fixed_role = 0)
         and (p.type_desc = N'SERVER_ROLE')
         and (p.name > @role_name)
      order by
         p.name;

      print N' * ' + nchar(9) + @role_name;
   
   end;

end;

-- Output the recreated principals

if exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc <> N'SERVER_ROLE')) begin

   print N' * ';
   print N' * Principals recreated by this script:';
   print N' * ';

   set @name = N'';

   while (exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc <> N'SERVER_ROLE') and (p.name > @name))) begin

      select top 1
         @name = p.name
      from
         @principals as p
      where
         (p.is_fixed_role = 0)
         and (p.type_desc <> N'SERVER_ROLE') 
         and (p.name > @name)
      order by
         p.name;

      print N' * ' + nchar(9) + @name;

   end;

end;

print N' *';
print N' */';

print N'';
print N'use master;';
print N'go';
print N'';



declare @principal_id          int          -- How we're addressing each principal
      , @sid                   varbinary(85)
      , @sid_string            nvarchar(512)
      , @type_desc             nvarchar(60)
      , @is_disabled           bit
      , @default_database_name sysname
      , @default_language_name sysname
      , @credential_id         int
      , @owning_principal_id   int
      , @is_fixed_role         bit
      , @password_hash         varbinary(256)
      , @password_string       nvarchar(4000)
      , @is_policy_checked     bit
      , @is_expiration_checked bit
      , @x                     xml
      , @options               nvarchar(4000)
      , @role_principal_id     int;

set @x = N'<root></root>';

set @role_name = N'';

-- Create the user-defined server roles

while (exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc = N'SERVER_ROLE') and (p.name > @role_name))) begin

   select top 1
      @role_name = p.name
    , @owning_principal_id = p.owning_principal_id
   from
      @principals as p
   where
      (p.is_fixed_role = 0)
      and (p.type_desc = N'SERVER_ROLE')
      and (p.name > @role_name)
   order by
      p.name;

   set @name = (
      select top 1
         sp.name
      from
         sys.server_principals as sp
      where
         (sp.principal_id = @owning_principal_id)
   );

   print N'print N''Creating user-defined server role ' + quotename(@role_name) + N'...'';';
   print N'go';

   print N'if not exists(select * from sys.server_principals where name = N''' + @role_name + N''')'
   print nchar(9) + N'create server role ' + quotename(@role_name) + N' authorization ' + quotename(@name) + N';';
   print N'go';
   print N'';
   
end;

set @name = N'';

-- Recreate principals

while (exists(select * from @principals as p where (p.is_fixed_role = 0) and (p.type_desc <> N'SERVER_ROLE') and (p.name > @name))) begin

   select top 1
      @name = p.name
    , @principal_id = p.principal_id
    , @sid = p.[sid]
    , @type_desc = p.type_desc
    , @is_disabled = p.is_disabled
    , @default_database_name = p.default_database_name
    , @default_language_name = p.default_language_name
    , @credential_id = p.credential_id
    , @owning_principal_id = p.owning_principal_id
    , @is_fixed_role = p.is_fixed_role
    , @password_hash = p.password_hash
    , @is_policy_checked = p.is_policy_checked
    , @is_expiration_checked = p.is_expiration_checked
   from
      @principals as p
   where
      (p.is_fixed_role = 0)
      and (p.type_desc <> N'SERVER_ROLE')
      and (p.name > @name)
   order by
      p.name;

   print N'print N''Begin principal: ' + quotename(@name) + N''';';
   print N'go';

   print N'print N''creating login for principal...'';';
   print N'go';

   print N'if not exists(select * from sys.server_principals where name = N''' + @name + N''')';
      
   set @tmpstr = null;
   set @options = null;

   if (@type_desc = N'SQL_LOGIN') begin

      if (@password_hash is not null) begin
            
         set @password_string = N'0x' + @x.value(N'xs:hexBinary(sql:variable("@password_hash"))', N'[nvarchar](4000)');

         set @options = N'password=' + @password_string + N' hashed';

      end else begin

         set @options = N'password=''''';

      end;
   
      set @sid_string = N'0x' + @x.value(N'xs:hexBinary(sql:variable("@sid"))', N'[nvarchar](512)');
   
      set @options = @options + N', sid=' + @sid_string;

      if (@is_expiration_checked is not null) set @options = coalesce(@options + N', ', N'') + N'check_expiration=' + case when @is_expiration_checked = 1 then N'on' else N'off' end;

      if (@is_policy_checked is not null) set @options = coalesce(@options + N', ', N'') + N'check_policy=' + case when @is_policy_checked = 1 then N'on' else N'off' end;

      if (@credential_id is not null) begin

         set @options = coalesce(@options + N', ', N'') 
                        + (select
                           c.name
                           from
                           sys.credentials as c
                           where
                           c.credential_id = @credential_id
                        );

      end;

   end else begin 
         
      if @type_desc in (N'WINDOWS_LOGIN', N'WINDOWS_GROUP') begin
   
         set @tmpstr = N' from windows';

      end;

   end;

   if (@include_db = 1) and (@default_database_name is not null) set @options = coalesce(@options + N', ', N'') + N'default_database=' + quotename(@default_database_name);

   if (@include_lang = 1) and (@default_language_name is not null) set @options = coalesce(@options + N', ', N'') + N'default_language=' + quotename(@default_language_name);

   print nchar(9) + N'create login ' + quotename(@name) + coalesce(@tmpstr, '') + coalesce(N' with ' + @options, N'') + N';'
   print N'go';

   if (@is_disabled = 1) begin

      print N'print N''disabling principal...'';';
      print N'go';

      print N'alter login ' + quotename(@name) + N' disable;'
      print N'go';

   end;

   if (@include_role = 1) and (exists(select * from @memberships as m where m.member_principal_id = @principal_id)) begin

      print N'print N''applying server roles for principal...'';';
      print N'go';

      set @role_principal_id = 0;

      while (exists(select * from @memberships as m where (m.member_principal_id = @principal_id) and (m.role_principal_id > @role_principal_id))) begin

         select top 1
            @role_principal_id = m.role_principal_id
         from
            @memberships as m
         where
            (m.member_principal_id = @principal_id)
            and (m.role_principal_id > @role_principal_id)
         order by
            m.role_principal_id;

         set @role_name = (
            select
               p.name
            from
               @principals as p
            where
               p.principal_id = @role_principal_id
         );

         set @tmpstr = N'alter server role ' + quotename(@role_name) + N' add member ' + quotename(@name) + N';';

         print @tmpstr;
         print N'go';

      end;

   end;

   print N'print N''End principal: ' + quotename(@name) + N''';';
   print N'go';
   print N'';

end;

drop table #temp;