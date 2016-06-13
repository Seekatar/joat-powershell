Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot Logger.psm1) -Verbose:$false

# script block for adding log messages to the queue
$_dataAdded = { 
					try
					{
				        if ($sender -and $sender[$event.SourceEventArgs.Index] -ne $null)
						{
				            $event.MessageData.LogList.Enqueue((New-PooledLogItem $sender[$event.SourceEventArgs.Index] $event.MessageData))
						}
					}
					catch 
					{
						Write-LogMessage Error "Exception in background thread writing output $_`n$($_.ScriptStackTrace)"
					}
			  }

# script block for adding output objects to the queue
$_outputDataAdded = {  
						try
						{
							if ( $sender -and $sender[$event.SourceEventArgs.Index] -ne $null)
							{ 
								$event.MessageData.LogList.Enqueue((New-PooledLogItem $sender[$event.sourceEventArgs.Index] $event.MessageData))
								if ( $event.MessageData.PassThru )
								{
									$event.MessageData._passThruOutput.Enqueue($sender[$event.sourceEventArgs.Index])
								}
							} 
						}
						catch 
						{
							Write-LogMessage Error "Exception in background thread writing output $_`n$($_.ScriptStackTrace)"
						}
					} 

<#
.Synopsis
	internal function for validating level
#>
function _level($y) 
{
    $set = "All","Debug","Verbose","Warning","OutputOnly","DebugOnly","VerboseOnly","WarningOnly","ErrorOnly"
    if ( $y -in $set ) 
	{
		$true
	} 
	else 
	{
		throw "The argument `"$y`" does not belong to the set `"$($set -join ",")`""
	}
}

<#
.Synopsis
	internal function for setting PowerShell streams on a PooledScript
#>
function _setStreams
{
param(
[Parameter(Mandatory)]
[Management.Automation.PSObject] $me,
[object] $posh
)
	$me._debug = $posh.Debug;
    $me._verbose = $posh.Verbose;
    $me._warning = $posh.Warning;
    $me._error = $posh.Error;
	
	$this._debugSourceId = [Guid]::NewGuid().ToString()
	$this._verboseSourceId = [Guid]::NewGuid().ToString()
	$this._warningSourceId = [Guid]::NewGuid().ToString()
	$this._errorSourceId = [Guid]::NewGuid().ToString()
	
	Register-ObjectEvent -InputObject $me._debug -EventName DataAdded -Action $_dataAdded -MessageData $me -SourceIdentifier $this._debugSourceId | Out-Null
	Register-ObjectEvent -InputObject $me._verbose -EventName DataAdded -Action $_dataAdded -MessageData $me -SourceIdentifier $this._verboseSourceId | Out-Null
	Register-ObjectEvent -InputObject $me._warning -EventName DataAdded -Action $_dataAdded -MessageData $me -SourceIdentifier $this._warningSourceId | Out-Null
	Register-ObjectEvent -InputObject $me._error -EventName DataAdded -Action $_dataAdded -MessageData $me -SourceIdentifier $this._errorSourceId  | Out-Null
}

<#
.Synopsis
	internal function for cleaning up a pooled script
#>
function _cleanup($me)
{
        try
        {
            $null = $me.Posh.EndInvoke($me.Result);
        }
        catch 
        {
            $me.HadErrors = $true;
            $me.Exception = $_;
        }
        $me.Posh.Dispose();
        $me.Posh = $null;
        $me.Result = $null;
}


<#
.Synopsis
	Get a summary for a PoolScript that has ended
	
.Description
	Get the name, exception, error, counts for the script.
	If -debug or -verbose are passed in, counts for those
	outputs are included
	
.Parameter script
	the script to show summary about, supports pipeline

.Outputs
	Summary report object

#>
function getCount( $list )
{
	$count = 0
	if( $list ) 
	{
		$count = @($list).Count
	}
	$count
}

function Get-PooledScriptSummary
{
[CmdletBinding()]
param
( 
[Parameter(Mandatory,ValueFromPipeline)]
[PSCustomObject] $script
)

	begin
	{
	}

	process
	{
		$properties = 'NameAndSuffix',
						@{n='HadException';e={$null -ne $_.Exception }},
						'HadErrors',
						@{n='Output';e={getCount $_.Output }},
						@{n='Warnings';e={getCount $_.Warning}},
						@{n='Error';e={getCount $_.Error}},
						'Ended'
						 

		if ( $VerbosePreference -ne 'SilentlyContinue')
		{
			$properties += @{n='Verbose';e={@($_.Verbose).Count}}
		}
		if ( $DebugPreference -ne 'SilentlyContinue' )
		{
			$properties += @{n='Debug';e={@($_.Debug).Count}}
		}
		
		$script | Select-Object -Property $properties										
	}
}

<#
.Synopsis
	Get errors and exception information from Pooled Scripts
	
.Parameter pooledScript
	the script to get details from

.Outputs
	string message about any errors.  Empty if none

#>
function Get-PooledScriptError
{
param(
[Parameter(ValueFromPipeline)]
[object] $pooledScript
)
begin
{
	$pooledScripts = @()
}

process
{
	$pooledScripts += $pooledScript
}

end
{
	$exceptionMsgs = $null
	foreach ( $p in $pooledScripts )
	{
		 $exceptionMsg = @($p.LogList | Get-PooledLogMessage -level ErrorOnly -raw | ForEach-Object {
			if ( $_.LogObject.Exception)
			{
				$msg = $_.LogObject.Exception.ToString()
			}
			if ( $_.LogObject.ScriptStackTrace )
			{
				$msg += [Environment]::NewLine+($_.LogObject.ScriptStackTrace)
			}
			Format-LoggerMessage -level Error -message $msg -timestamp $_.Timestamp -source $p.NameAndSuffix
			}) -join [Environment]::NewLine

		if ( $exceptionMsgs )
		{
			$exceptionMsgs += [Environment]::NewLine
		}
		$exceptionMsgs += $exceptionMsg
	}

	if ( $exceptionMsgs )
	{	
		return "Errors in PooledScripts$([Environment]::NewLine)$exceptionMsgs"
	}
	else
	{
		return $null
	}
}
}

<#
.Synopsis
	Write messages logged to the background script to the appropriate stream
	
.Description
	Uses Write-LogMessage to write to appropriate stream

.Parameter logList
	pooledScript or logList of messages

.Parameter level
	the log level to output to log, defaults to Warning

#>
function Write-PooledScriptMessage
{
[CmdletBinding(DefaultParameterSetName="string")]
param( 
[Parameter(ValueFromPipeline)]
[Object] $logList, 
[ValidateScript({_level $_})]
[string]$level = "Warning"
)
	
process
{
	Get-PooledLogMessage -logList $logList -level $level -raw | ForEach-Object {
		$logItem = $_
		
		$prev = $VerbosePreference
		$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
		
		if ( $logItem.LogObject -is [System.Management.Automation.DebugRecord]) { Write-LogMessage Debug -message $logItem.LogObject -timestamp $logItem.Timestamp }
		elseif ( $logItem.LogObject -is [System.Management.Automation.VerboseRecord]) { Write-LogMessage Verbose -message $logItem.LogObject -timestamp $logItem.Timestamp }
		elseif ( $logItem.LogObject -is [System.Management.Automation.WarningRecord]) { Write-LogMessage Warning -message $logItem.LogObject -timestamp $logItem.Timestamp }
		elseif ( $logItem.LogObject -is [System.Management.Automation.ErrorRecord]) { Write-LogMessage Error -message $logItem.LogObject -timestamp $logItem.Timestamp }
		else { Write-LogMessage Info -message $logItem -timestamp $logItem.Timestamp }
		
		$VerbosePreference = $prev
	}
}

}

<#
.Synopsis
	Writes any errors and exception information to Write-Error
	
.Parameter pooledScript
	the script to get details from

.Outputs
	None, Writes to Write-Error is any errors

#>
function Write-PooledScriptError
{
param(
[Parameter(ValueFromPipeline)]
[object] $pooledScript
)
begin
{
	$pooledScripts = @()
}

process
{
	$pooledScripts += $pooledScript
}

end
{
	$exceptionMsg = $pooledScripts | Get-PooledScriptError 
	if ( $exceptionMsg )
	{
		Write-LogMessage Error $exceptionMsg
	}
}
}

<#
.Synopsis
	Get log messages from a PooledScript that has ended
	
.Description
	Depending on the level, different messages and output is returned

.Parameter logList
	LogList object from a PooledScript that has completed

.Parameter level
	the level of output to return

.Parameter includeTime
	include the timestamp of the output

.Parameter includeName
	include the script name in the output

.Parameter timeFormat
	format for the time, if output.  Defaults to "u"
	
.Parameter raw
	if set, returns PowerShell log objects, otherwise returns strings

.Outputs
	string versions of log messages

#>
function Get-PooledLogMessage 
{ 
[OutputType([array])]
[CmdletBinding(DefaultParameterSetName="string")]
param( 
[Parameter(ValueFromPipeline)]
[Object] $logList, 
[ValidateScript({_level $_})]
[string]$level = "Warning",
[Parameter(ParameterSetName="string")]
[switch] $includeTime, 
[Parameter(ParameterSetName="string")]
[switch] $includeName, 
[Parameter(ParameterSetName="string")]
[string] $timeFormat,
[Parameter(ParameterSetName="raw")]
[switch] $raw)

process
{
	if ( $includeTime -and -not $timeFormat )
	{
		$timeFormat = (Get-LoggingConfig).timestampFormat
	}

    if ( -not $loglist )
	{
        return New-Object System.Management.Automation.PSDataCollection[PSObject]
	}

	$debug   = $level -eq "All" -or $level -eq "Debug" -or $level -eq "DebugOnly"
	$verbose = $level -eq "All" -or $level -eq "Debug" -or $level -eq "Verbose" -or $level -eq "VerboseOnly"
	$warning = $level -eq "All" -or $level -eq "Debug" -or $level -eq "Verbose" -or $level -eq "Warning" -or $level -eq "WarningOnly"
	$errors  = $level -eq "All" -or $level -eq "Debug" -or $level -eq "Verbose" -or $level -eq "Warning" -or $level -eq "ErrorOnly"
	$output  = $level -eq "All" -or $level -eq "OutputOnly"
	
    $list = $loglist | Where-Object {
       	($_.LogObject -is [System.Management.Automation.DebugRecord] -and $debug) -or
       	($_.LogObject -is [System.Management.Automation.VerboseRecord] -and $verbose) -or
       	($_.LogObject -is [System.Management.Automation.WarningRecord] -and $warning) -or
       	($_.LogObject -is [System.Management.Automation.ErrorRecord] -and $errors) -or
        ($_.LogObject -isnot [System.Management.Automation.InformationalRecord] -and $_.LogObject -isnot [System.Management.Automation.ErrorRecord] -and $output)
    } 
	if ( -not $raw )
	{
		$list = $list | ForEach-Object { $_.ToString( $includeTime, $includeName, $true, $timeFormat ) }
	}
	@($list)
}

}
    
<#
.Synopsis
	create a log list object for passing to a pool of scripts if you want them to share a log
	
.Outputs
	a log list object

#>
function New-PooledLogList()
{
    return New-Object System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]
}

<#
.Synopsis
	Create a new log item for background thread

.Description
	Resulting object has the following members:
		Timestamp
		LogObject
		Script
		ToString($includeTime, $includeName,$includeType)
	
.Parameter logObject
	the object logged (error, info, warn, verbose log object)

.Parameter pooledScript
	optional script that logged the message

.Outputs
	a log item object with the properties and methods in Description

#>
function New-PooledLogItem
{
	param(
		[Parameter(Mandatory)]
		[object] $logObject,
		[PSCustomObject] $pooledScript
	)
	
	$logItem = [PSCustomObject] @{ 	Timestamp = [DateTimeOffset]::Now;
							 		LogObject = $logObject;
							 		Script = $pooledScript; }
	
	Add-Member -InputObject $logItem -MemberType ScriptMethod -Name `
	ToString -Value { 
		param( 
			[bool] $includeTime = $false, 
			[bool] $includeName = $false, 
			[bool] $includeType = $true, 
			[string] $timeFormat = "G" )

        $prefix = ""
        if ($includeTime)
		{
            $prefix = "$($this.Timestamp.ToString($timeFormat)) "
		}
		$name = ""
        if ($includeName)
		{
            $name += "[" + ($this.Script.NameAndSuffix) + "] "
		}

        if ($this.LogObject -is [System.Management.Automation.DebugRecord])
		{
			if ($includeType)
			{
				$prefix += "[DEBUG] $name" 
			}
            return $prefix + ($this.LogObject.ToString())
		}
        elseif ($this.LogObject -is [System.Management.Automation.VerboseRecord])
		{
			if ($includeType)
			{
				$prefix += "[VERBOSE] $name"
			}
            return $prefix + ($this.LogObject.ToString())
		}
        elseif ($this.LogObject -is [System.Management.Automation.WarningRecord])
		{
			if ($includeType)
			{
				$prefix += "[WARNING] $name" 
			}
            return $prefix + ($this.LogObject.ToString())
		}
        elseif ($this.LogObject -is [System.Management.Automation.ErrorRecord])
        {
            $x = $this.LogObject -as [System.Management.Automation.ErrorRecord]
            $msg = "{0}\n{1}\n{2}" -F $x.ToString(), $x.ErrorDetails, $x.ScriptStackTrace
			if ($includeType)
			{
				$prefix += "[ERROR] $name" 
			}
            return $prefix + $msg;
        }
        else
		{
			if ($includeType)
			{
				$prefix += "[OUTPUT] $name" 
			}
            return $prefix + ($this.LogObject | Out-String)
		}
	} -Force
	
	return $logItem
}


<#
.Synopsis
	Create a pooled script object(s) using common script and name
	
.Parameter ArgumentList
	hash table of parameters for the script

.Parameter name
	the friendly name for the script to run

.Parameter scriptBlock
	the script block to run

.Parameter suffix
	optional suffix for appending to the name to distinguish threads.  If not supplied an incrementing number is used

.Parameter logList
	optional log list if sharing logs between threads. New-PooledLogList will create one.

.Outputs
	Pooled script object

#>
function New-PooledScript
{
param(
	[Parameter(Mandatory)]
	[string] $name,
	[Parameter(Mandatory)]
	[scriptBlock] $scriptBlock,
	[Parameter(ValueFromPipeline)]
	[hashTable] $argumentList,
	[string] $suffix,
	[Object] $logList
)

process
{
	if ( $null -eq $logList )
	{
		$logList = New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject];
	}
	elseif ( $logList.Count -gt 0 )
	{
		throw "List object not empty.  Cannot reuse list if not empty"
	}
	
	$pooledScript = [PSCustomObject] @{ Name = $name;
								  PassThru = $false;
								  Posh = $null;
								  Suffix = $suffix;
								  ScriptBlock = $scriptBlock;
								  ArgumentList = $argumentList;
								  Result = $null;
								  HadErrors = $false;
								  Exception = $null;
								  TimedOut = $false;
								  Ended = $false;
								  LogList = $logList;
								  LogFileName = $null;
								  _debug  = New-Object System.Management.Automation.PSDataCollection[PSObject];
								  _verbose = New-Object System.Management.Automation.PSDataCollection[PSObject];
								  _warning  = New-Object System.Management.Automation.PSDataCollection[PSObject];
								  _error = New-Object System.Management.Automation.PSDataCollection[PSObject];
								  _output  = New-Object System.Management.Automation.PSDataCollection[PSObject];
								  _passThruOutput  = New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject];
								  _outputSourceId = $null; 
								  _debugSourceId = $null;
								  _verboseSourceId = $null;
								  _warningSourceId = $null;
								  _errorSourceId = $null;
								}

    # Gets the name and suffix as a string for logging
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name NameAndSuffix -Value { "{0} - {1}" -f $this.Name, $this.Suffix }

    # Gets the Debug messages 
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name Debug -Value { Get-PooledLogMessage -logList $this.LogList -level "DebugOnly" -raw }

    # Gets the Verbose messages 
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name Verbose -Value { Get-PooledLogMessage -logList $this.LogList -level "VerboseOnly" -raw }

    # Gets the Warning messages 
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name Warning -Value { Get-PooledLogMessage -logList $this.LogList -level "WarningOnly" -raw }

    # Gets the Error messages 
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name Error -Value { Get-PooledLogMessage -logList $this.LogList -level "ErrorOnly" -raw }

    # Gets the Output messages 
	Add-Member -InputObject $pooledScript -MemberType ScriptProperty -Name Output -Value { Get-PooledLogMessage -logList $this.LogList -level "OutputOnly" -raw }

	# Runs the scriptblock for the thread
	Add-Member -InputObject $pooledScript -MemberType ScriptMethod -Name Run -Value $scriptBlock

	# Gets all the log messages in order, combining debug, verbose, warning, and error
	# if want the string version, use Get-PooledLogMessage
	Add-Member -InputObject $pooledScript -MemberType ScriptMethod -Name `
	GetMessages -Value { 
	param( 
	[ValidateScript({_level $_})]
	[string]$level = "Warning" 
	)
		$list = @(Get-PooledLogMessage -logList $this.LogList -level $level -raw:$true)
		@($list)
	}
							
	# Gets the pass thru output.
	# non null if any is available.  Call until null
    Add-Member -InputObject $pooledScript -MemberType ScriptMethod -Name GetPassThruOutput -Value { 
	
		$output = $null
        if ($this._passThruOutput.TryDequeue([ref] $output))
    	{
        	return $output;
    	}
		else
		{
			return $null
		}
	}
	
	# called when the thread is starting
    Add-Member -InputObject $pooledScript -MemberType ScriptMethod -Name `
	Starting -Value { 
	param(
	[Parameter(Mandatory)]
	[Management.Automation.PowerShell] $posh,
	[Parameter(Mandatory)]
	[int] $index 
	)        
		$this.Posh = $posh;
		_setStreams $this $this.Posh.Streams
		if ( -not $this.Suffix )
		{
			$this.Suffix = $index.ToString();
		}
		$this._output = New-Object System.Management.Automation.PSDataCollection[PSObject]
		$this._outputSourceId = [Guid]::NewGuid().ToString()
		Register-ObjectEvent -InputObject $this._output -EventName DataAdded -Action $_outputDataAdded -MessageData $this -SourceIdentifier $this._outputSourceId | Out-Null
	}
	
	# called when script is stopping
    Add-Member -InputObject $pooledScript -MemberType ScriptMethod -Name `
	Stopped -Value {
	[CmdletBinding()]
	param([switch] $timedOut)
	
		Write-Verbose "Unregistering events for $($this.NameAndSuffix)"
		if ( $this._outputSourceId )
		{
			Unregister-Event -SourceIdentifier $this._outputSourceId -Force -ErrorAction Ignore
		}
		if ( $this._debugSourceId )
		{
			Unregister-Event -SourceIdentifier $this._outputSourceId -Force -ErrorAction Ignore
			Unregister-Event -SourceIdentifier $this._verboseSourceId -Force -ErrorAction Ignore
			Unregister-Event -SourceIdentifier $this._warningSourceId -Force -ErrorAction Ignore
			Unregister-Event -SourceIdentifier $this._errorSourceId -Force -ErrorAction Ignore
		}
		
        $this.Ended = $true;
        $this.TimedOut = $timedOut;
        if ($this.Posh)
        {
            $this.HadErrors = $this.Posh.HadErrors;
            if ($timedOut)
            {
				Write-LogMessage Verbose "Starting BeginStop on timed out script '$($this.NameAndSuffix)', had errors is $($this.Posh.HadErrors)"
                $null = $this.Posh.BeginStop( {$null = $args[0].Posh.EndStop($args[0]); _cleanup $this}, $this )
            }
            else
            {
                _cleanup $this
            }
        }

		Write-LogMessage Verbose "Finished BeginStop on '$($this.NameAndSuffix)', Exception is $([bool]($this.Exception))"
        # if have syntax error Dispose clears the error collection, copy it
		if ($this.Exception )
		{
			# add exception as error and to loglist, if it exists
			$exceptions = @( New-Object System.Management.Automation.ErrorRecord -ArgumentList $this.Exception.Exception,"Script exception", "NotSpecified", $null)
			# this closes collection, so have to add all in one shot
			$this.LogList.Enqueue((New-PooledLogItem $exceptions[0] $this))
		}
		if ( $this.LogFileName )
		{
			Add-LogFile $this.LogFileName 
			Remove-Item $this.LogFileName -ErrorAction Ignore
		}
		Write-LogMessage Verbose "Finished stopped on '$($this.NameAndSuffix)'"
    }
																							
	return $pooledScript
}

}

function _createSessionState($importModules, $loggerFileNameSuffix )
{
	$logFileName = $null
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if($ImportModules)
    {
		# paths must be fully qualified to work
		$paths = $ImportModules | ForEach-Object { Resolve-Path( $_ ) }

        $InitialSessionState.ImportPSModule($paths) | Out-Null
		Write-Verbose "Imported $paths"

		if ( [bool]($ImportModules | Where-Object { $_ -eq (Join-Path $PSScriptRoot "logger.psm1") }))
        {
			$loggerConfig = Get-LoggingConfig
			$loggerConfig.logName += "_$loggerFileNameSuffix"
			$logFileName = $loggerConfig.logName 
    	    $InitialSessionState.Variables.Add( (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList "_logger_config", $loggerConfig, "config for logger") )
        }
    }
	return $InitialSessionState,$logFileName
}

<#
.Synopsis
	Invoke any number of scripts in parallel using a runspace pool.
	
.Description.
	The PooledScript encapsulates data about the script to run, and 
	all its output streams.
	
		To get messages of all types in order a LogList is used in a PooledScript.
	Multiple PooledScripts can share one log to have all messages ordered.
	
	See Add-PooledScriptType for all the members used to setup and 
	get data after a script runs.
		
.Parameter PooledScript
	a PooledScriptBlock with a scriptblock, name, etc. To execute

.Parameter MinimumThreads
	min number of threads to run (defaults to 1)

.Parameter MaximumThreads
	max number of threads to run (default to 10)

.Parameter PassThru
	if set output is written immediately for all scripts, otherwise all it output when all complete

.Parameter ShowProgress
	if set shows progress 

.Parameter ImportModules
	any modules to import into all runspaces

.Outputs
	output from the scripts
	
.Example
	$logList = New-PooledLogList
	
	$tests = @()

	$tests += $webSites | Where-Object {$_.type -eq 'Excalibur'-or $_.type -eq 'WebService'} | ForEach-Object { New-PooledScript -Name "CacheErrors: $($_.Url)" -ScriptBlock {param($url) $url | Test-CacheError} -ArgumentList @{url=$_.Url} -LogList $logList }
	
	$tests | Invoke-PooledScript -ShowProgress -ImportModules (Join-Path $PSScriptRoot DeployHelpers.psm1) -PassThru 

	Get-Messages $logList 'Warning' $true $true
	
	This shares one log list for all the scripts, then shows all the warning and error output
	prefixing it with the timestamp and PooledScript name
	
#>
function Invoke-PooledScript
{
[CmdletBinding()]
param( 
[Parameter(Mandatory,ValueFromPipeline)]
[object] $PooledScript,
[ValidateRange(1,100)]
[int] $MinimumThreads = 1,
[ValidateRange(1,100)]
[int] $MaximumThreads = 10,
[string] $activityName = "Running pooled scripts",
[switch] $PassThru,
[switch] $ShowProgress,
[string[]] $ImportModules,
[switch] $usePools
)


begin
{ 
	if ( $MinimumThreads -gt $MaximumThreads )
	{
		$MaximumThreads = $MinimumThreads
	}
	
	if ( $usePools )
	{
	    $InitialSessionState, $logFileName = _createSessionState $importModules ""

		$pool =  [RunspaceFactory]::CreateRunspacePool($MinimumThreads, $MaximumThreads, $InitialSessionState, $Host)
		$pool.ApartmentState = "STA"
		$pool.open()
	}
	else
	{
		$pool = $null 
	}

    $pooledScripts = @()
	
	$progressId = 9876  # random

	if ( $ImportModules )
	{
		foreach ( $p in $ImportModules )
		{
			if ( -not (Test-Path $p -PathType Leaf))
			{
				Write-LogMessage Error "Import module passed to Invoke-Pooled script not found: $p"
			}
		}
	}
}

process
{
	if ( $pooledScript.Ended )
	{
		throw "Can't resuse Ended script with name '$($pooledScript.name)!'"
	}
	$pooledScripts += $pooledScript
}


end 
{
	$startTime = Get-Date
	$TerminateAllThreads = $false
	
	# check for Ctrl+C or other keys. 
	function checkForBreak()
	{
		try 
		{
	        #Check for Control + C
	        if ([Console]::KeyAvailable)
	        {
	            $key = [Console]::ReadKey($true)
	            if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C"))
	            {
					if ( -not $TerminateAllThreads  )
					{
		                Write-LogMessage Warning "The user terminated the process using Ctrl + C"
						$TerminateAllThreads = $true
					}
					# else already processed it
	            }
				elseif (($key.Modifiers -band ([ConsoleModifiers]"Alt" -bor [ConsoleModifiers]"Control")) -eq 0 )
				{
					# Query the status and show it if press Q
					if ( $key.key -eq "Q" )
					{
	                    Write-LogMessage Info ("Running or pending scripts ({0:f2} secs since started):" -f ((Get-Date) - $startTime).TotalSeconds) 
	                    foreach ( $t in $pooledScripts | Where-Object { -not $_.Ended })
	                    {
	                        Write-LogMessage Info "    $($t.NameAndSuffix)" # Write-LogMessage Info ok
	                    }
					}
				}
	        }
		}
		catch 
		{
			Write-LogMessage Warning "Exception in Console processing`n$_`n$($_.ScriptStackTrace)"
			if ( $global:error.Count -gt 0 )
			{
				$global:error.RemoveAt(0) # remove this error to avoid false positive
			}
		}
		return $TerminateAllThreads 
	}
	
	$TerminateAllThreads = $false
	try 
	{
	
        #allows us to trap Ctrl + C and cancel the threads...
        try { [Console]::TreatControlCAsInput = $true } 
		catch {		
			if ( $global:error.Count -gt 0 )
			{
				$global:error.RemoveAt(0) # remove this error to avoid false positive
			}
		}
    
		$index = 0
		
		$inputStream = (New-Object System.Management.Automation.PSDataCollection[PSObject])
		$inputStream.Complete()

        foreach( $p in $pooledScripts)
        {
            $posh = [PowerShell]::Create().AddScript($p.ScriptBlock) 
			$p.Starting($posh,$index++)
			$p.PassThru = $PassThru
			
            if ( $p.ArgumentList )
			{
				$posh.AddParameters($p.ArgumentList ) | Out-Null
			}
			if ( $usePools )
			{
				$posh.RunspacePool = $pool
			}
			else
			{
				$InitialSessionState, $logFileName = _createSessionState $importModules $p.NameAndSuffix
				$p.LogFileName = $logFileName
				$runspace = [RunspaceFactory]::CreateRunspace($Host,$InitialSessionState)
				$runspace.Open()
				$posh.Runspace = $runspace 
			}

			Write-LogMessage Verbose "Starting pooled script: '$($p.NameAndSuffix)' with logFileName of '$logFileName' and PassThru of $PassThru"
			
			$p.Result = $posh.BeginInvoke( $inputStream, $p._output )
        }
		
        if( $ShowProgress ) 
		{ 
			Write-Progress -Id $progressId -Activity $activityName -Status ("Starting {0} scripts..." -f $pooledScripts.Count) -PercentComplete 0 -CurrentOperation "Waiting for scripts to complete."
		}

        $running = $true
		$completed = 0
        while($running)
        {
            $breakIt = checkForBreak 
			if ( $breakIt )
			{
				$TerminateAllThreads = $TerminateAllThreads -or $breakIt
				$VerbosePreference = 'Continue' # turn on verbose so we can see if there are problems killing threads
			}
			$running = $false
			
            foreach ($p in $pooledScripts | Where-Object { -not $_.Ended} )
            {
				$running = $true

				$outObj = $null
				do 
				{
					Write-Verbose "Checking pass thru output for $($p.NameAndSuffix)"
					$outObj = $p.GetPassThruOutput()
					if ( $outObj )
					{
						Write-Verbose "PassThru!"
						Write-Output $outObj
					}
				}
				while ($outObj)
				
                if( $p -and $TerminateAllThreads)
                {
                    $completed += 1
                    If ($ShowProgress) 
					{ 
						Write-Progress -Id $progressId -Activity $activityName -Status "Terminating all scripts..." -CurrentOperation $p.NameAndSuffix -PercentComplete (100*$completed/($pooledScripts.Count)) 
					}
					Write-LogMessage Verbose "Stopping $($p.NameAndSuffix)"
					$p.Stopped($true)
                }
                elseif ($p.Result.IsCompleted)
                {
                    $completed += 1
					try
					{
						$p.Stopped($false)
						
						if ( -not $PassThru -and $p._output -and $p._output.Count )
						{
							Write-LogMessage Verbose "Sending objects not passed thru"
							$p._output
						}
					}
					catch
					{
						Write-LogMessage Error "Exception stopping $($p.NameAndSuffix)`n$_`n$_.ScriptStackTrace"
					}
					
                    if ($ShowProgress) 
					{ 
						Write-Progress -Id $progressId -Activity $activityName -Status ("Completed {0}/{1}" -f $completed,$pooledScripts.Count) `
										-CurrentOperation ("Last completed script: '{0}'" -f $p.NameAndSuffix)`
										-PercentComplete (100*$completed/($pooledScripts.Count)) 
					}
                }
			}
            
			Start-Sleep -Milliseconds 25
        }
		
        if( $pool -and -not ($pool.IsDisposed)) 
		{ 
			$pool.Close(); 
			$pool.Dispose() 
		}
        If ($ShowProgress) 
		{ 
			Write-Progress -Id $progressId -Completed -Activity $activityName 
		}
	}
	catch 
	{
		Write-LogMessage Error "Exception in Invoke-PooledScript! $_`n$($_.ScriptStackTrace)"
	}
	finally
	{
        try { [Console]::TreatControlCAsInput = $false } 		
		catch 
		{		
			if ( $global:error.Count -gt 0 )
			{
				$global:error.RemoveAt(0) # remove this error to avoid false positive
			}
		}
		# append any log files not yet appended
		$pooledScripts | Where-Object { $_ -and $_.LogFileName -and (Test-Path $_.LogFileName) } | ForEach-Object { $_.LogFileName } | Add-LogFile

	}
	if ( $TerminateAllThreads )
	{
		Write-LogMessage Warning "Exiting since cancelled"
		throw "User canceled"
	}
}
}

Export-ModuleMember -Function "*-*"