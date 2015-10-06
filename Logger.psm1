Set-StrictMode -Version Latest

$script:startTime = $null

# helper to clear all script variables
function _init
{
	$script:logName = $null
    $script:timestamp = $false
    $script:timestampFormat = $null
	$script:includeDebugInFile = $false
	$script:source = $null
}

<#
.Synopsis
	Sets the settings for the logger, usually just use the Start-Logging
	
.Description
	This is usually used when nesting logging in where another RunSpace or
	PowerShell prompt should use the same log file.  This sets the settings
	like the constructor, but does not emit the header
	
.Parameter logFileName
	the fully qualified path to a log file

.Parameter timestampEachLine
	set to prepend each line with a timestamp

.Parameter dateFormat
	format to use when timestamping.  Passes it to [DateTimeOffset]::ToString

.Parameter append
	set to append to an existing log

.Parameter includeDebugInFile
	set to include Debug messages in the log file, usually too noisy
	
.Parameter defaultSource
	default source for logging each line
	
.Outputs
	none
#>
function Set-LoggingConfig($logName,$timestamp,$timestampFormat,$includeDebugInFile,$defaultSource="")
{
	$script:logName = $logName
	$script:timestamp = $timestamp
	$script:timestampFormat = $timestampFormat
	$script:includeDebugInFile = $includeDebugInFile
	$script:source = $defaultSource
}

# if globals set, use them.  PoolsScript sets these so background thread can log 
# with parent's log settings and know the name of the log file
if ( (Get-Variable _logger_logName -Scope Global -ErrorAction Ignore) )
{
	Set-LoggingConfig  -logName $global:_logger_logName -timestamp $global:_logger_timestamp -timestampFormat $global:_logger_timeFormat `
					   -includeDebugInFile $global:_logger_includeDebugInFile -defaultSource $global:_logger_source
}
else
{
	_init
}

<#
.Synopsis
	Get the settings currently used by the logger
	
.Outputs
	logname, timestamp (bool), timestampFormat, includeDebugInFile

#>
function Get-LoggingConfig
{
	$script:logName,$script:timestamp,$script:timestampFormat,$script:includeDebugInFile,$script:source
}

<#
.Synopsis
	Start logging to a file, emitting a header to the file
	
.Parameter logFileName
	the fully qualified path to a log file

.Parameter timestampEachLine
	set to prepend each line with a timestamp

.Parameter dateFormat
	format to use when timestamping.  Passes it to [DateTimeOffset]::ToString

.Parameter append
	set to append to an existing log

.Parameter includeDebugInFile
	set to include Debug messages in the log file, usually too noisy
	
.Outputs
	none

.Example
	Start-Logging C:\temp\test.log -timestampEachLine -includeDebugInFile
	
	Start logging to a file, timestamping and including debug messages

#>
function Start-Logging
{
param(
[string] $logFileName,
[switch] $timestampEachLine,
[string] $dateFormat = "yyyy-MM-dd HH:mm:ss,fff", # log4net's format
[switch] $append,
[switch] $includeDebugInFile,
[string] $defaultSource = ""
)
	if ( Get-IsLogging )
	{
		if ( $logFileName -ne $script:logName )
		{
			Write-LogMessage Error "Can't log to $logFileName since already logging to $script:logName"
		}
		else 
		{
			Write-LogMessage Warning "Start-Logging on same file: $logFileName.  Not usually recommended."
		}
		return
	}
	
	$start = @"
*********************************
* Starting logging into $logFileName
* Start time: $([DateTimeOffset]::Now)
* User: $env:USERNAME
* User domain: $env:USERDOMAIN
* Machine: $env:COMPUTERNAME
* Path: $PSScriptRoot
* PowerShell Version: $($PSVersionTable.psversion.tostring())
* Host: $((get-host).Name)
*********************************
"@	
	try
	{
		if ( $append )
		{
			Add-Content -Path $logFileName -Value $start
		}
		else
		{
			Set-Content -Path $logFileName -Value $start
		}
		Set-LoggingConfig -logName $logFileName -timestamp $timestampEachLine -timestampFormat $dateFormat `
							-includeDebugInFile $includeDebugInFile -defaultSource $defaultSource
		$script:startTime = [DateTimeOffset]::Now
		Write-LogMessage Verbose "Logging started to $script:logName"
	}
	catch 
	{
		Write-Error "Error initializing log file $logFileName`n$_"
		$script:logName = $null
	}
}

<#
.Synopsis
	Stops logging by writing a trailer and clearing log settings
	
.Outputs
	None

#>
function Stop-Logging
{
	if ( Get-IsLogging )
	{
		$end = [DateTimeOffset]::Now
		Add-Content -Path $script:logName -Value @"
*********************************
* Stopping logging
* End time: $end
* Elapsed: $("{0:0.00}" -f ($end - $script:startTime).TotalMinutes) minutes
*********************************
"@	
		Write-Host "Logging stopped. Output is in $script:logName"
		$script:logName = $null
	}
}

<#
.Synopsis
	Tests to see if already logging
	
.Outputs
	$true if logging

#>
function Get-IsLogging
{
	$script:logName -ne $null
}

<#
.Synopsis
	log a message to the file
#>
function _logMessage
{
param(
[Parameter(Mandatory)]	
[AllowEmptyString()]
[string] $message,
[ValidateSet("Debug","Verbose","Info","Warning","Error")]
[string] $level	= "Info",
[string] $source
)

	if ( Get-IsLogging )
	{
		$prefix = "[$($level.ToUpper())] "
		if ( -not $source )
		{
			$source = $script:source
		}
		if ( $source )
		{
			$prefix += "[$source] "
		}
	
		if ( $script:timestamp )
		{
			$now = [DateTimeOffset]::Now
			# don't double up on timestamp
			if ( $message.ToString() -like ("{0}*" -f $now.ToString("yyyy-MM-dd")) -or $message.ToString() -like ("{0}*" -f $now.ToString("MM/dd/yyyy")) )
			{
				$prefix = "" # can't put prefix on it since starts with timestamp
			}
			else
			{
				$prefix = "$($now.ToString($script:timestampFormat)) $prefix"
			}
		}
		if ( $level -ne "Debug" -or $script:includeDebugInFile )
		{
			Add-Content -path $script:logName -Value "$prefix$message"
		}
	}
}

function Format-LoggerMessage
{
[CmdletBinding()]
param(
[ValidateSet("Debug","Verbose","Info","Warning","Error")]
[string] $level	= "Info",
[Parameter(Mandatory,ValueFromPipeline)]	
[AllowEmptyString()]
[AllowNull()]
[string] $message,
[DateTimeOffset] $timestamp = [DateTimeOffset]::Now,
[string] $source
)
	$prefix = "[$($level.ToUpper())] "

	if ( $script:timestamp )
	{
		$now = $timestamp
		# don't double up on timestamp
		if ( $message.ToString() -like ("{0}*" -f $now.ToString("yyyy-MM-dd")) -or $message.ToString() -like ("{0}*" -f $now.ToString("MM/dd/yyyy")) )
		{
			$prefix = "" # can't put prefix on it since starts with timestamp
		}
		else
		{
			$prefix = "$($now.ToString($script:timestampFormat)) $prefix"
		}
	}
	if ( $source ) 
	{
		$prefix += "[$source] "
	}

	"$prefix $message"
}

<#
.Synopsis
	Add a file to the log
	
.Description
	Appends a file to the currently logging file

.Parameter path
	path to file to append, must exist

.Parameter delimit
	set to add delimiters before and after the appended data

.Outputs
	None

#>
function Add-LogFile
{
[CmdletBinding()]
param(
[Parameter(ValueFromPipeLine)]
$path,
[switch] $delimit
)

process
{
	if ( Get-IsLogging )
	{
		if ( Test-Path $path -PathType Leaf )
		{
			if ( $delimit )
			{
				_logMessage (">"*80)
				_logMessage ">> Begin insert of file $path"
				_logMessage (">"*80)
			}
			Get-Content $path | Add-Content -Path $script:logName 
			if ( $delimit )
			{
				_logMessage (">"*80)
				_logMessage "<< End insert of file $path"
				_logMessage (">"*80)
			}
		}
		else
		{
			Write-LogMessage Warning "Can't append file '$path' since it does not exist"
		}
	}
	else
	{
		Write-LogMessage Warning "Not logging.  Ignoring adding file $path"
	}
}
}

<#
.Synopsis
	Write a message to the log file
	
.Parameter message
	the message to write

.Parameter level
	the level of the message, defaults to Info

.Parameter BackgroundColor
	for Info messages, can specify color

.Parameter ForegroundColor
	for Info messages, can specify color

.Outputs
	None

#>
function Write-LogMessage
{
[CmdletBinding()]
param(
[ValidateSet("Debug","Verbose","Info","Warning","Error")]
[string] $level	= "Info",
[Parameter(Mandatory,ValueFromPipeline)]	
[AllowEmptyString()]
[AllowNull()]
[object] $message,
[ConsoleColor] $BackgroundColor,  
[ConsoleColor] $ForegroundColor
)

process
{
	if ( -not $message )
	{
		$message = "" # allow blank lines
	}
	
	try
	{
		$m = $message
		if ( $message -and $message -isnot [string] )
		{
			$m = ($message | Out-String)
		}
		_logMessage $m $level 
	}
	catch 
	{
		Write-Error "Error trying to log to '$script:logName' message '$message'`n$_`n$($_.ScriptStackTrace)" # Write-Error ok
	}
	
	switch ($level)
	{ 
		"Debug"		{ 
						# get the Debug setting from the parent, session
						$prev = $DebugPreference
						$DebugPreference = $PSCmdlet.GetVariableValue('DebugPreference')
						Write-Debug $message
						$DebugPreference = $prev
					}
		"Verbose"  	{ 	
						# get the verbose setting from the parent, session
						$prev = $VerbosePreference
						$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
						Write-Verbose $message
						$VerbosePreference = $prev
					}
		"Warning" 	{ Write-Warning $message; }
		"Error" 	{ Write-Error $message; }
		"Info" 		{  # could do (Get-host).UI.RawUI.ForegroundColor, but that depends on running in certain hosts
			if ( $ForegroundColor -and $BackgroundColor )
			{
				Write-Host $message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor 
			}
			elseif ( $ForegroundColor)
			{
				Write-Host $message -ForegroundColor $ForegroundColor 
			}
			elseif ( $BackgroundColor)
			{
				Write-Host $message -BackgroundColor $BackgroundColor 
			}
			else
			{
				Write-Host $message 
			}
			
		}
	}
}
}

Export-ModuleMember -Function "*-*" 