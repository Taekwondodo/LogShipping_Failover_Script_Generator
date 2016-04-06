/*
 * Server Principals Script
 * For all SQL Authenticated and Windows Authenticated principals on SQL-LOGSHIP-P
 * Including default database, default language and server roles
 * Generated Apr  1 2016  4:17PM
 *
 * Server privileges are not recreated by this script!
 *
 * Principals recreated by this script:
 *
 * 	PBRC\AlexanDE
 * 	PBRC\leblanea
 * 	PBRC\secleblanea
 * 	PBRC\VedrosMJ
 * 	SQL-LOGSHIP-P\SQLServer2005MSFTEUser$SQL-LOGSHIP-P$MSSQLSERVER
 * 	SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER
 * 	SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER
 *
 */
 
use master;
go
 
print N'Begin principal: [PBRC\AlexanDE]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'PBRC\AlexanDE')
	create login [PBRC\AlexanDE] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [PBRC\AlexanDE];
go
print N'End principal: [PBRC\AlexanDE]';
go
 
print N'Begin principal: [PBRC\leblanea]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'PBRC\leblanea')
	create login [PBRC\leblanea] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [PBRC\leblanea];
go
print N'End principal: [PBRC\leblanea]';
go
 
print N'Begin principal: [PBRC\secleblanea]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'PBRC\secleblanea')
	create login [PBRC\secleblanea] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [PBRC\secleblanea];
go
print N'End principal: [PBRC\secleblanea]';
go
 
print N'Begin principal: [PBRC\VedrosMJ]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'PBRC\VedrosMJ')
	create login [PBRC\VedrosMJ] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [PBRC\VedrosMJ];
go
print N'End principal: [PBRC\VedrosMJ]';
go
 
print N'Begin principal: [SQL-LOGSHIP-P\SQLServer2005MSFTEUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'SQL-LOGSHIP-P\SQLServer2005MSFTEUser$SQL-LOGSHIP-P$MSSQLSERVER')
	create login [SQL-LOGSHIP-P\SQLServer2005MSFTEUser$SQL-LOGSHIP-P$MSSQLSERVER] from windows with default_database=[master], default_language=[us_english];
go
print N'End principal: [SQL-LOGSHIP-P\SQLServer2005MSFTEUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
 
print N'Begin principal: [SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER')
	create login [SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER];
go
print N'End principal: [SQL-LOGSHIP-P\SQLServer2005MSSQLUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
 
print N'Begin principal: [SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
print N'creating login for principal...';
go
if not exists(select * from sys.server_principals where name = N'SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER')
	create login [SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER] from windows with default_database=[master], default_language=[us_english];
go
print N'applying server roles for principal...';
go
alter server role [sysadmin] add member [SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER];
go
print N'End principal: [SQL-LOGSHIP-P\SQLServer2005SQLAgentUser$SQL-LOGSHIP-P$MSSQLSERVER]';
go
 
