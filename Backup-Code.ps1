<#
.Synopsis
	Backup code to backup folders. wzzip.exe is required
	
.Description
	Runs wzzip.exe to backup file using an exclude file exclude 
	non-source code files.  By default uses the archive flag to 
	determine what to backup

.Parameter folderToBackup
	folder name to backup, defaults to current one

.Parameter days
	number of days to look back, defaults to 5

.Parameter noArchive
	if set will not use the archive bit
	
.Parameter backupFolders
	array of one or more strings to backup to.  Usually first is a local folder and second is a remote one.

#>
[CmdletBinding()]
param(
[ValidateScript({Test-Path $_ -PathType Container})]
[string] $folderToBackup = $PWD,
[int] $days = 5,
[switch] $noArchive,
[ValidateCount(1,100)]
[string[]] $backupFolders = ("c:\ariel\archive","\\sbcsystems.local\users\$($env:username)\archive\"),
[string] $excludeFile = "$($env:USERPROFILE)\documents\bin\zipexcludes.txt"
)

foreach ( $b in $backupFolders )
{
	$Error.Clear
	if ( -not (Test-Path $b -PathType Container ))
	{
		Write-Error "Path doesn't exist: $b"
	}
	if ( $Error )
	{
		exit 9
	}
}

if ( $excludeFile -and -not (Test-Path $excludeFile -PathType Leaf )
{
	Write-Warning "Skipping excludes since exclude file doesn't exist: $excludeFile"
	$excludeFile = $null
}

$folder = (Split-Path $folderToBackup -Leaf)
Write-Debug "Folder is $folder"
$now = [DateTime]::Now
$when = $now.AddDays(-$days)

$fname = "${folder}_{0}" -f $now.ToString("yyMMdd-HHmm")
$fullName = Join-Path $backupFolders[0]  "${fname}.zip"

Write-Host "Backing up to ${fname}.zip from $when to $now..."

$parms = @()
$parms += "-r"
$parms += "-p"
if ( $days -gt 0 )
{
	$parms += "-td$days"
}

if ( -not $noArchive )
{
	Write-Host "   only files not already archived"
	$parms += "-i"
}

$excludes = ""
if ( $excludeFile )
{
	$excludes = "-x@$excludeFile"
}
Write-Verbose "& `"c:\Program Files (x86)\winzip\wzzip`" $($parms -join " ") $excludes `"$fullName`" *.*"

& "c:\Program Files (x86)\winzip\wzzip" @parms $excludes "$fullName" *.*

if ( $LASTEXITCODE -ne 0 )
{
	Write-Error "Non-zero exit code from wzzip: $LASTEXITCODE"
	exit 1
}
Write-Host "...complete"

foreach ( $b in $backupFolders | Select-Object -Skip 1 )
{
	Write-Host "Copying $fullName to $b"
	Copy-Item $fullName $b
}
Write-Host "All done"
