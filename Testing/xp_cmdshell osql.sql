/*
exec sp_configure 'show advanced options', 1;
reconfigure;
exec sp_configure 'xp_cmdshell', 1;
reconfigure;
*/
exec master.dbo.xp_cmdshell 'osql -E -SSQL-LOGSHIP-p -w 200 -n -i"\\pbrc.edu\files\share\MIS\DBA\Log Shipping Lab\Script Generators\Git\Logshipping Scripts\Recreating Databases\get logins v2 2005 fix.sql" -o""\\pbrc.edu\files\share\MIS\DBA\Log Shipping Lab\Script Generators\Git\Testing\test.sql""';