<#
.SYNOPSIS
Get a list of config data names from file

.PARAMETER Path
Path to the config file

.PARAMETER NameLike
Like string to filter results

.EXAMPLE
An example

.OUTPUTS
Name of members matching the NameLike
#>
function Find-ConfigData
{
[CmdletBinding()]
param(
[string] $NameLike = '*',
[string] $Path = "$env:home/myconfig.json"
)
    Set-StrictMode -Version Latest

	if ( -not (Test-Path $Path -PathType Leaf))
	{
		throw "Path $Path not found"
	}

    $object = Get-Content $path -Raw | ConvertFrom-Json
    Get-Member -InputObject $object -MemberType NoteProperty | Where-Object Name -like $NameLike | Select-Object -ExpandProperty Name
}