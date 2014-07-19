Set-StrictMode -Version Latest

if ( -not (Get-Variable dbTrace -Scope global -ErrorAction Ignore) )
{
	$global:dbTrace = $false
}

<#
 do this to get Print statements from SQL
#>
function _registerForEvent( $Conn )
{
	Unregister-Event -SourceIdentifier ADOHelper.GetDbRows -Force -ErrorAction Ignore
	# there's also $event.SourceEventArgs.Errors which is a System.Data.SqlClient.SqlErrorCollection of System.Data.SqlClient.SqlError
	$null = Register-ObjectEvent -InputObject $Conn -EventName InfoMessage -SourceIdentifier ADOHelper.GetDbRows -Action { Write-Host $event.SourceEventArgs.Message }
}

<#
helper to unregister from the output events
#>
function _unregisterEvent()
{
	Unregister-Event -SourceIdentifier ADOHelper.GetDbRows -Force -ErrorAction Ignore
}

<#
helper to open the connection, database
#>
function _openAll( $dbConnectionString, $timeout = 1200 )
{
	if ( $dbConnectionString -like "*.sdf" )
	{
		# SQLServer CE, load the type
		if ( Test-Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server Compact Edition\v3.5" )
		{	
			$dir = (Get-ItemProperty -path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server Compact Edition\v3.5" -Name installdir).installdir
			Add-Type -Path (Join-Path $dir "Desktop\System.Data.SqlServerCe.dll")
			
			$Conn = New-Object System.Data.SqlServerCe.SqlCeConnection($dbConnectionString)
			$Cmd = New-Object System.Data.SqlServerCe.SqlCeCommand
			$timeout = 0
		}
		else
		{
			throw "SQLServer CE 3.5 does not appear to be installed.  Can't open sdf file"
		}
	}
	else
	{
		$Conn = New-Object System.Data.SqlClient.SqlConnection($dbConnectionString)
		$Cmd = New-Object System.Data.SqlClient.SqlCommand
	}
	_registerForEvent $Conn
	$Conn.Open()
	$Cmd.Connection = $Conn
	$Cmd.CommandTimeout = $timeout
	
	if ( $global:dbTrace )
	{
		$Cmd.CommandText = 'select @@SPID'
		$spid = $Cmd.ExecuteScalar()
		Write-Host "Opened cmd with spid of $spid" -ForegroundColor Cyan
	}
	Write-Output $Conn
	Write-Output $Cmd
}

<#
helper to close the connection, database
#>
function _closeAll( $Cmd, $Conn )
{
	if ( $global:dbTrace )
	{
		$Cmd.CommandText = 'select @@SPID'
		$spid = $Cmd.ExecuteScalar()
		Write-Host "Closing cmd with spid of $spid" -ForegroundColor Cyan
	}
	if ( $Cmd -ne $null )
	{
		try { $cmd.Dispose() } 
		catch 
		{
			Write-Warning "Error closing cmd $_"
		}
	}
	if ( $Conn -ne $null )
	{
		try
		{
			try
			{
			$Conn.ChangeDatabase('master') # sometimes conn kept alive, this at least switched off another db
			}
			catch {}
			
			if ( $global:dbTrace )
			{
				Write-Host "Closing conn" -ForegroundColor Cyan
			}
			$Conn.Close()
			if ( $global:dbTrace )
			{
				Write-Host "Conn's state is now $($Conn.State)" -ForegroundColor Cyan
			}
			$Conn.Dispose()
		}
		catch 
		{
			Write-Warning "Error closing conn $_"
		}
	}
}

<#
.Synopsis
	Execute a non-query on the database

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Parameter dbConnectionString
	the connection string

.Parameter command
	the command to run 
	
.Parameter scalar
	true if execute as scalar command, otherwise executes as non query
	
.Parameter wantCount
	set if you want the rowsAffected returned if not scalar
	
.Outputs
	number of rows affected, or nothing if wantCount is false
#>
Function Invoke-DbNonQuery
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
[string]$server,
[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
[string] $dbName,
[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
[string]$dbConnectionString,
[Parameter(Position=1,Mandatory,ParameterSetName="ConnStr")]
[Parameter(Position=2,Mandatory,ParameterSetName="Server")]
[string] $command,
[switch] $scalar,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200,
[switch] $wantCount
)

	$ret = $null
	$Cmd = $null
	$Conn = $null
	
	if ( $server -and $dbName )
	{
		$dbConnectionString = "Server=$server;Initial Catalog=$dbName;Integrated Security=True;MultipleActiveResultSets=True"
	}

	if ( $PSCmdlet.ShouldProcess($dbConnectionString, $command ) )
	{
		try
		{
			#Setting Up Sql Connection/Command objects & opening the connection
			$Conn, $Cmd = _openAll $dbConnectionString $timeoutSecs

			$Cmd.CommandText = $command
			
			if ( $scalar )
			{
				$ret = $Cmd.ExecuteScalar()
			}
			else
			{
				$ret = $Cmd.ExecuteNonQuery()
			}
			
			_unregisterEvent
		}
		catch
		{
			throw "Error processing ${command}:`r`n" +  ($_ | Out-String )
		}
		finally
		{
			_closeAll $Cmd $Conn
		}	
	}		
	if ( $wantCount -or $scalar )
	{
		return $ret
	}
}

<#
.Synopsis
	Execute a scalar query on the database

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Parameter dbConnectionString
	the connection string

.Parameter command
	the command to run 
	
.Outputs
	the scalar value
#>
Function Invoke-DbScalar
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
[string]$server,
[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
[string] $dbName,
[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
[string]$dbConnectionString,
[Parameter(Position=1,Mandatory,ParameterSetName="ConnStr")]
[Parameter(Position=2,Mandatory,ParameterSetName="Server")]
[string] $command,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200
)
	Invoke-DbNonQuery @PSBoundParameters -scalar 
}

<#
.Synopsis
	Execute one or more non queries on the database

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Parameter dbConnectionString
	the connection string

.Parameter commands
	strings that make up the commands, separate multiple commands with a line starting with GO, can pipe a file in
	
#>
function Invoke-DbNonQueries
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
[string]$server,
[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
[string] $dbName,
[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
[string]$dbConnectionString,
[Parameter(Position=1,ParameterSetName="ConnStr")]
[Parameter(Position=2,ParameterSetName="Server")]
[Parameter(ValueFromPipeline=$true)]
[String] $commands,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200
)
	begin
	{
		if ( $server -and $dbName )
		{
			$dbConnectionString = "Server=$server;Initial Catalog=$dbName;Integrated Security=True;MultipleActiveResultSets=True"
		}

		$tmpSql = $null
		
		#Setting Up Sql Connection/Command objects & opening the connection
		$Conn, $Cmd = _openAll $dbConnectionString -timeoutSecs $timeoutSecs
	}
	
	process
	{
		try
		{
			$s = $commands
			If($s.trim() -like "go*")
			{
				If($tmpSql -and $tmpSql.Trim()) 
				{ 
					if ( $PSCmdlet.ShouldProcess($dbConnectionString, $tmpSql.Trim() ) )
					{
						$Cmd.CommandText = $tmpSql
						
						$ret = $Cmd.ExecuteNonQuery()
					}
				}
				$tmpSql = $null
			}
			Else
			{
				$tmpSql += [System.Environment]::NewLine
				$tmpSql += $s
			}
		}
		catch 
		{
			_closeAll $Cmd $Conn
			throw "Error processing ${tmpSql}:`r`n" +  ($_ | Out-String )
		}
	}
	
	end
	{
		if($tmpSql)
		{
			if ( $PSCmdlet.ShouldProcess($dbConnectionString, $tmpSql.Trim() ) )
			{
				$Cmd.CommandText = $tmpSql
				
				$ret = $Cmd.ExecuteNonQuery()
			}
		}
		_unregisterEvent		
		_closeAll $Cmd $Conn
	}
}



<#
.Synopsis
	Execute a query on the database, calling the scriptblock for each row

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Parameter dbConnectionString
	the connection string

.Parameter fn
	a script block to process the rows.  See the example for details

.Parameter query
	query to run
	
.Example
	Run a query and add each first column to an array
	
	Get-DbRow $connStr { param([System.Data.SqlClient.SqlDataReader]$reader) $Script:uiSites += ,$reader[0] } $uiSiteSql 

.Example

	Run a query and add each first column to an array
	
	ExecuteQuery $server mydatabasename { param([System.Data.SqlClient.SqlDataReader]$reader) $Script:uiSites += ,$reader[0] } $uiSiteSql
#>
Function Get-DbRow
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
[string]$server,
[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
[string] $dbName,
[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
[string]$dbConnectionString,
[Parameter(Position=2,Mandatory)]
[scriptblock]$fn,
[Parameter(Position=3,Mandatory)]
[string] $query,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200
)

	if ( $server -and $dbName )
	{
		$dbConnectionString = "Server=$server;Initial Catalog=$dbName;Integrated Security=True;MultipleActiveResultSets=True"
	}

	$ret = $null
	$Cmd = $null
	$Conn = $null
	try
	{
		if ( $PSCmdlet.ShouldProcess($dbConnectionString, $query ) )
		{
			#Setting Up Sql Connection/Command objects & opening the connection
			$Conn, $Cmd = _openAll $dbConnectionString -timeoutSecs $timeoutSecs

			$Cmd.CommandText = $query
			
			$ret = $Cmd.ExecuteReader()
			while ( $ret.Read() )
			{
				& $fn $ret
			}
		}
	}
	catch
	{
		throw "Error processing ${query}:`r`n" +  ($_ | Out-String )
	}
	finally
	{
		_unregisterEvent		
		
		if ( $ret )
		{
			$ret.Close()
		}
		if ( $Cmd -and $Conn )
		{
			_closeAll $Cmd $Conn
		}
	}	
}

<#
.Synopsis
	Returns objects with properties named for columns in query

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Parameter dbConnectionString
	the connection string

.Parameter query
	query to run

.Outputs
	objects for each row

.Example
	PS C:\d\temp> ExecuteObjectQueryConnStr "Data Source=c:\d\temp\Sbc.Client.Assembly.DevTrunk.Dev.themes.sdf" "select a.name, t.name as TYPE, cast(a.version_major as nvarchar(30))+'.'+cast(a.version_minor as nvarchar(30)) as VERSION from artifact a join artifact_type t on a.artifact_type_id = t.artifact_type_id" | ft -a

	Get the artifact and types from a SQLServer CE file
#>
Function Get-DbObjects
{
	[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
	param(
	[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
	[string]$server,
	[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
	[string] $dbName,
	[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
	[string]$dbConnectionString,
	[Parameter(Position=1,Mandatory,ParameterSetName="ConnStr")]
	[Parameter(Position=2,Mandatory,ParameterSetName="Server")]
	[string]$query,
	[ValidateRange(1,100000)]
	[int] $timeoutSecs = 1200
	)
	
	if ( $server -and $dbName )
	{
		$dbConnectionString = "Server=$server;Initial Catalog=$dbName;Integrated Security=True;MultipleActiveResultSets=True"
	}

	$script:result = @()
	
	Get-DbRow -dbConnectionString $dbConnectionString -query $query -fn {  param([System.Data.Common.DbDataReader]$reader)
				$cols = @{}
				for ( $i = 0; $i -lt $reader.FieldCount; $i++ )
				{
					$cols[$reader.GetName($i)] = $reader[$i]
				}
				$script:result += New-Object PSObject -Property $cols
			} -timeoutSecs $timeoutSecs -Verbose:($VerbosePreference -ne 'SilentlyContinue') -WhatIf:$WhatIfPreference
			
	return $script:result			
}

<#
.Synopsis
	Does the database exists

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Outputs
	true if it exists on the server
#>
Function Test-DatabaseExists
{
	param(
	[Parameter(Position=0, Mandatory)]
	[string]$server,
	[Parameter(Position=1, Mandatory)]
	[string] $dbName
	)
	
	return $(Invoke-DbScalar $server "master" "SELECT  1 FROM    sys.databases WHERE   name = '$dbName' " ) -eq 1
}

<#
.Synopsis
	Does the database exists and is online

.Parameter server
	SQL Server

.Parameter dbName
	database name

.Outputs
	true if it exists on the server
#>
Function Test-DatabaseOnline
{
	param(
	[Parameter(Position=0, Mandatory)]
	[string]$server,
	[Parameter(Position=1, Mandatory)]
	[string] $dbName
	)
	
	return $(Invoke-DbScalar $server "master" "SELECT  1 FROM    sys.databases WHERE   name = '$dbName' and state = 0 " ) -eq 1
}

Set-Alias Get-DatabaseExists Test-DatabaseExists 
Set-Alias ExecuteNonQueries Invoke-DbNonQueries
Set-Alias ExecuteQuery Get-DbRow
Set-Alias ExecuteObjectQuery Get-DbObjects
Set-Alias ExecuteNonQuery Invoke-DbNonQuery
Set-Alias ExecuteScalar Invoke-DbScalar

Export-ModuleMember -Function 'Execute*','*-*' -Alias *