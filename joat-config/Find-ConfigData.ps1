<#
.SYNOPSIS
Get a list of config data names from file

.PARAMETER NameLike
Like string to filter results

.PARAMETER Path
Path to the config file

.EXAMPLE
Find-ConfigData

Get all the keys in the file

.EXAMPLE
Find-ConfigData Keys.*

Get all the keys that start with 'Keys.'

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

New-Alias -Name fcfgd -Value Find-ConfigData