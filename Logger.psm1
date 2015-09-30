Set-StrictMode -Version Latest

if ( (Get-Variable _logger_logName -Scope Global -ErrorAction SilentlyContinue) -and (Test-Path $global:_logger_logName) )
{
    $script:logName = $global:_logger_logName
    $script:timestamp = $global:_logger_timestamp
    $script:timestampFormat = $global:_logger_timeFormat
    #Write-Warning "Logger using global settings of '$script:logName' '$script:timestamp' '$script:timestampFormat'"
}
else
{
    $script:logName = $null
    $script:startTime = $null
    $script:timestamp = $false
    $script:timestampFormat = $null
}

function Get-LoggerSettings
{
	$script:logName,$script:timestamp,$script:timestampFormat
}

function Set-LoggerSettings($logName,$timestamp,$timestampFormat)
{
	$script:logName = $logName
	$script:timestamp = $timestamp
	$script:timestampFormat = $timestampFormat
}

<#
.Synopsis
	Start logging to a file
	
.Parameter logFileName
	the fully qualified path to a log file

.Parameter timestampEachLine
	set to prepend each line with a timestamp

.Parameter dateFormat
	format to use when timestamping.  Passes it to [DateTimeOffset]::ToString

.Parameter append
	set to append to an existing log

.Outputs
	none

#>
function Start-Logging
{
param(
[string] $logFileName,
[switch] $timestampEachLine,
[string] $dateFormat = "u",
[switch] $append
)
	if ( Get-IsLogging )
	{
		Write-LogMessage Error "Already logging to $script:logName"
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
	if ( $append )
	{
		Add-Content -Path $logFileName -Value $start
	}
	else
	{
		Set-Content -Path $logFileName -Value $start
	}
	$script:logName = $logFileName
	$script:startTime = [DateTimeOffset]::Now
	$script:timestamp = $timestampEachLine
	$script:timestampFormat = $dateFormat
	Write-LogMessage Verbose "Logging started to $script:logName"
}

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

function _logMessage
{
param(
[Parameter(Mandatory)]	
[AllowEmptyString()]
[string] $message,
[ValidateSet("Debug","Verbose","Info","Warning","Error")]
[string] $level	= "Info"
)

	if ( Get-IsLogging )
	{
		$prefix = ""
		if ( $script:timestamp )
		{
			$now = [DateTimeOffset]::Now
			# don't double up on timestamp
			if ( $message.ToString() -like ("{0}*" -f $now.ToString("yyyy-MM-dd")) -or $message.ToString() -like ("{0}*" -f $now.ToString("MM/dd/yyyy")) )
			{
			}
			else
			{
				$prefix = "$($now.ToString($script:timestampFormat)) "
			}
		}
		Add-Content -path $script:logName -Value "$prefix$message"
	}
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
				_logMessage ">>>>>> Begin insert of file $path"
			}
			Get-Content $path | Add-Content -Path $script:logName 
			if ( $delimit )
			{
				_logMessage "<<<<<< End insert of file $path"
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
	
	$prefix = "[$($level.ToUpper())] "
	
	try
	{
		$m = $message
		if ( $message -and $message -isnot [string] )
		{
			$m = ($message | Out-String)
		}
		_logMessage "$prefix$m" $level
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