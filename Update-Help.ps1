<#
.Synopsis
    Update the PowerShell README.md file.  Run before committing to update it
#>
[CmdletBinding()]
param(
[string] $Path,
[string[]] $FolderExcludes,
[switch] $Recurse
)
if ( -not $Path )
{
  $Path = $PWD
}
if ( !(Test-Path (Join-Path $Path "README.md")))
{
  throw "Must be in a folder with README.md.  Create an empty one if this is the correct folder: $Path"
}

Push-Location $Path

$fname = (Join-Path $Path "README.md")
$readme = (Get-Content $fname -Raw)

# strip out previously generated content
$regex = New-Object Text.RegularExpressions.Regex "^# Command Synopses.*", ('singleline', 'multiline')

$replacement = & (Join-Path $PSScriptRoot New-HelpOutput.ps1) -FolderExcludes $FolderExcludes -Recurse:$Recurse
Set-Content -Path $fname -Value ($regex.Replace($readme, "")) # replacing with $replacement loses newlines, Add-Content
Add-Content -Path $fname -Value $replacement

Pop-Location
