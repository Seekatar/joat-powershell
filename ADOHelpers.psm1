Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot Logger.psm1)

if ( -not (Get-Variable dbTrace -Scope global -ErrorAction Ignore) )
{
	$global:dbTrace = $false
}

$script:ADOPrintHandlerDefault = {
    param($msg) 
    Write-Host $msg
    }

# needs to be global since event can't get it from $Script:
$global:ADOPrintHandler = $script:ADOPrintHandlerDefault 

<#
.Synopsis
	Set the handler for handling PRINT statments in SQL

.Parameter sb
	The script block that takes a $msg parameter

.Outputs
	The current script block, so you can restore it
#>
function Set-ADOPrintHandler
{
[Parameter(Mandatory)]
param(
[scriptblock] $sb 
) 
 
	$prev = $global:ADOPrintHandler; 
	$global:ADOPrintHandler = $sb; 
	$prev 
}

function _writeTraceMessage( $msg )
{
	if ( $global:dbTrace )
	{
		Write-Host $msg -ForegroundColor Cyan # write-host ok
	}
}

<#
 do this to get Print statements from SQL
#>
function _registerForEvent( $Conn )
{
	Unregister-Event -SourceIdentifier ADOHelper.GetDbRows -Force -ErrorAction Ignore
	# there's also $event.SourceEventArgs.Errors which is a System.Data.SqlClient.SqlErrorCollection of System.Data.SqlClient.SqlError
	if ( $global:ADOPrintHandler )
	{
		$null = Register-ObjectEvent -InputObject $Conn -EventName InfoMessage -SourceIdentifier "ADOHelper.GetDbRows" -Action {
			 Invoke-Command -scriptBlock $global:ADOPrintHandler -arg $event.SourceEventArgs.Message }
	}
	else 
	{
		_writeTraceMessage "No registration since null handler"
	}
}

<#
helper to unregister from the output events
#>
function _unregisterEvent()
{
	Unregister-Event -SourceIdentifier ADOHelper.GetDbRows -Force -ErrorAction Ignore
}

<#
.Synopsis
	helper to open the connection, database

.Outputs
	connection, command
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
		_writeTraceMessage "Opened cmd with spid of $spid" 
	}
	Write-Output $Conn
	Write-Output $Cmd
}

<#
helper to close the connection, database
#>
function _closeAll( $Cmd, $Conn )
{
	$hadError = [bool]$Error

	_unregisterEvent

	
	if ( $global:dbTrace )
	{
		$Cmd.CommandText = 'select @@SPID'
		$spid = $Cmd.ExecuteScalar()
		_writeTraceMessage "Closing cmd with spid of $spid" 
	}
	if ( $Cmd )
	{
		try { $cmd.Dispose() } 
		catch 
		{
			Write-LogMessage Warning "Error closing cmd $_"
		}
	}
	if ( $Conn  )
	{
		try
		{
			try
			{
				$Conn.ChangeDatabase('master') # sometimes conn kept alive, this at least switched off another db
			}
			catch 
			{
				Write-LogMessage Error "Error trying to re-use connection:`n$_"
			}
			
			if ( $global:dbTrace )
			{
				_writeTraceMessage "Closing conn" 
			}
			$Conn.Close()
			if ( $global:dbTrace )
			{
				_writeTraceMessage "Conn's state is now $($Conn.State)" 
			}
			$Conn.Dispose()
		}
		catch 
		{
			Write-LogMessage Warning "Error closing conn $_"
		}
	}
	
	if ( -not $hadError -and $Error )
	{
		$Error.Clear() # don't let this stop deploy
	}

}

function _setParameters( $parameters, $Cmd )
{
	$Cmd.Parameters.Clear()
	if ( $parameters )
	{
		foreach ( $p in $parameters.Keys )
		{
			$key = $p
			if ( $p -notlike "@*" )
			{
				$key = "@$p"
			}
			_writeTraceMessage "Adding parameter $key = $($parameters[$p])"
			$null = $Cmd.Parameters.AddWithValue($p,$parameters[$p])
		}
	}
}

function _formatExceptionMessage( $serverName, $sql, $theError )
{
	$msg = "Error executing SQL on $serverName"

	if ( $theError.Exception -and $theError.Exception.InnerException -and $theError.Exception.InnerException -is [System.Data.SqlClient.SqlException])
	{
		$e = $theError.Exception.InnerException
		if ( $e.Procedure )
		{
			$msg += ("`nMsg {0}, Level {1}, State {2}, Procedure {3}, Line {4}`n" -f $e.Number, $e.Class, $e.State, $e.Procedure, $e.LineNumber)
		}
		else 
		{
			$msg += ("`nMsg {0}, Level {1}, State {2}, Line {3}`n" -f $e.Number, $e.Class, $e.State, $e.LineNumber)
		}
		
		$msg += "$($theError.Exception.InnerException.Message)`n$($theError.ScriptStackTrace)"  
	}
	else
	{
		$msg += "`n"+$theError.ToString()+"`n"+$theError.ScriptStackTrace.ToString()
	}
	$msg += "`n$sql"

	$msg
}

function _runSql
{
[CmdletBinding(SupportsShouldProcess)]
param
( $tmpSql, $cmd, $dbConnnectionString, $scalar, $queries, $wantCount, $dontThrow )

	If($tmpSql -and $tmpSql.Trim()) 
	{ 
		if ( $PSCmdlet.ShouldProcess($dbConnectionString, $tmpSql.Trim() ) )
		{
			try 
			{
				$Cmd.CommandText = $tmpSql
				_setParameters $parameters $Cmd
				_writeTraceMessage "executing: $tmpSql"
						
				if ( $scalar )
				{
					$ret = $Cmd.ExecuteScalar()
					_writeTraceMessage "Scalar return is $ret"
					$ret 
				}
				elseif ( $queries )
				{
					$ret = $Cmd.ExecuteReader()
					while ( $ret.Read() )
					{
						Invoke-Command -ScriptBlock $fn -ArgumentList $ret 
					}
					while ( $ret.NextResult() )
					{
						while ( $ret.Read() )
						{
							Invoke-Command -ScriptBlock $fn -ArgumentList $ret 
						}
					}
					$ret.Close()
				}
				else
				{
					$ret = $Cmd.ExecuteNonQuery()
					if ( $wantCount )
					{
						_writeTraceMessage "Want count return is $ret"
						$ret
					}
				}
            }
            catch
            {
				if ( $dontThrow )
				{
					Write-LogMessage Warning "Exception running SQL: $tmpSql`n$_"
				}
				else
				{
					throw "Exception running SQL: $tmpSql`n$_"
				}
            }
		}
	}
}

function _invokeSql
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[string]$server,
[string] $dbName,
[string]$dbConnectionString,
$Conn,
$cmd,
[Parameter(ValueFromPipeline=$true)]
[String] $command,
[hashtable] $parameters,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200,
[switch] $queries,
[scriptblock] $fn,
[switch] $scalar,
[switch] $wantCount,
[switch] $dontThrow
)

	begin
	{
		$openedConn = -not $conn -and -not $cmd
		if ( $openedConn )
		{
			if ( $server -and $dbName )
			{
				$dbConnectionString = "Server=$server;Initial Catalog=$dbName;Integrated Security=True;MultipleActiveResultSets=True"
			}
			elseif ( -not $dbConnectionString )
			{
				throw "Invalid parameters.  Must supply connection, database, or connection string"
			}


			#Setting Up Sql Connection/Command objects & opening the connection
			$Conn, $Cmd = _openAll $dbConnectionString -timeoutSecs $timeoutSecs
		}

		$tmpSql = $null
	}
	
	process
	{
		try
		{
			if ( $PSCmdlet.ShouldProcess($server,"Execute SQL"))
			{
				$s = $command
				If($s.trim() -like "go*")
				{
					_runSql $tmpSql $cmd $dbConnectionString $scalar $queries $wantCount $dontThrow
					$tmpSql = ""
				}
				Else
				{
					$tmpSql += [System.Environment]::NewLine
					$tmpSql += $s
				}
			}
		}
		catch 
		{
			if ( $openedConn )
			{
				_closeAll $Cmd $Conn
				$Cmd = $null
				$Conn = $null
			}
			$theError = $_
			throw (_formatExceptionMessage $dbConnectionString $tmpSql $theError)
		}
	}
	
	end
	{
		Write-LogMessage Verbose "In end"
		if($tmpSql)
		{
			_runSql $tmpSql $cmd $dbConnectionString $scalar $queries $wantCount $dontThrow
		}
		if ( $openedConn -and $cmd )
		{
			_closeAll $Cmd $Conn
		}
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
	
.Parameter timeoutSecs
	timeout for connection in seconds, defaults to 120 (2 minutes)
	
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
[hashtable] $parameters,
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
	
.Parameter parameters
	optional hash table of substitution values.  If name not prefixed with @, will add it

.Parameter timeoutSecs
	timeout for connection in seconds, defaults to 120 (2 minutes)
	
#>
function Invoke-DbNonQuery
{
[CmdletBinding(DefaultParameterSetName="Server",SupportsShouldProcess)]
param(
[Parameter(Position=0,Mandatory,ParameterSetName="Server")]
[string]$server,
[Parameter(Position=1,Mandatory,ParameterSetName="Server")]
[string] $dbName,
[Parameter(Position=0,Mandatory,ParameterSetName="ConnStr")]
[string]$dbConnectionString,
[Parameter(Position=2,ValueFromPipeline)]
[Alias("commands")]
[String] $command,
[hashtable] $parameters,
[switch] $scalar,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200,
[switch] $wantCount,
[switch] $dontThrow
)
	

begin
{
	# get pipeline so we cascade it from this script
    $outBuffer = $null
    if ($PSBoundParameters.TryGetValue(‘OutBuffer’, [ref]$outBuffer))
    {
        $PSBoundParameters[‘OutBuffer’] = 1
    }
    $wrappedCmd = Get-command "_invokeSql" 
    $sb = {& $wrappedCmd @PSBoundParameters } 

    $sp = $sb.GetSteppablePipeline($myInvocation.CommandOrigin)
	$count = 0
	$sp.Begin($PSCmdLet)
}

process
{
	$sp.Process($_)
}

end
{
	$sp.End()
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
	
.Parameter parameters
	optional hash table of substitution values.  If name not prefixed with @, will add it
	
.Outputs 
	None

.Example
	Run a query and add each first column to an array
	
	@script:uiSites = @() 
	Get-DbRow $connStr { param([System.Data.SqlClient.SqlDataReader]$reader) $Script:uiSites += ,$reader[0] } $uiSiteSql 

.Example

	Run a query and add each first column to an array
	
	@script:uiSites = @() 
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
[hashtable] $parameters,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200
)

	_invokeSql -server $server -dbName $dbName -dbConnectionString $dbConnectionString -command $query -timeoutSecs $timeoutSecs -queries -fn $fn -parameters $parameters
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

.Parameter parameters
	optional hash table of substitution values.  If name not prefixed with @, will add it
	
.Parameter timeoutSecs
	timeout for connection in seconds, defaults to 120 (2 minutes)
	
.Outputs
	objects for each row

.Example
	PS C:\d\temp> ExecuteObjectQueryConnStr "Data Source=c:\d\temp\Sbc.Client.Assembly.DevTrunk.Dev.themes.sdf" "select a.name, t.name as TYPE, cast(a.version_major as nvarchar(30))+'.'+cast(a.version_minor as nvarchar(30)) as VERSION from artifact a join artifact_type t on a.artifact_type_id = t.artifact_type_id" | ft -a

	Get the artifact and types from a SQLServer CE file
#>
Function Get-DbObject
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
[hashtable] $parameters,
[ValidateRange(1,100000)]
[int] $timeoutSecs = 1200
)
	
	$script:count = 0
	
	function makeName([string] $colName)
	{
		# change non-word values to _
		if ( $colName )
		{
			return ($colName -replace "\W+", "_")
		}
		else
		{
			$script:count++
			return "NoColName$script:count"
		}
	}
	
	$script:result = @()
	_invokeSql -server $server -dbName $dbName -dbConnectionString $dbConnectionString -command $query -timeoutSecs $timeoutSecs -queries -parameters $parameters -fn {  param([System.Data.Common.DbDataReader]$reader)
				$cols = @{}
				for ( $i = 0; $i -lt $reader.FieldCount; $i++ )
				{
					$cols[(makeName($reader.GetName($i)))] = $reader[$i]
				}
				$script:result += New-Object PSObject -Property $cols
			} 
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
Function Test-Database
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

# old names now alias to more PShelly names
Set-Alias Get-DbObjects Get-DbObject 
Set-Alias Get-DatabaseExists Test-Database 
Set-Alias ExecuteNonQueries Invoke-DbNonQueries
Set-Alias ExecuteQuery Get-DbRow
Set-Alias ExecuteObjectQuery Get-DbObject
Set-Alias ExecuteNonQuery Invoke-DbNonQuery
Set-Alias ExecuteScalar Invoke-DbScalar
Set-Alias Invoke-DbNonQueries Invoke-DbNonQuery

Export-ModuleMember -Function 'Execute*','*-*' -Alias * -Variable 'ADOPrintHandler*'