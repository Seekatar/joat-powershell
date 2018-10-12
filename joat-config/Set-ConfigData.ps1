<#
.SYNOPSIS
Set data in a JSON config file

.PARAMETER Path
Path to the config file

.PARAMETER Name
Name of the config data to get

.PARAMETER Value
Object to save in the config.  May be simple or an object to ConvertTo-Json

.PARAMETER AsSecureString
Return the encrypted data as a SecureString

.PARAMETER Encrypt
Encrypt the data when storing it.  Only the current user can decrypt it.

.NOTES
Currently encryption only supported on Windows.  On Linux/OSX secure the config file.

.EXAMPLE
Set-ConfigData -Name ItemName -Value "testing123" $env:home/myconfig.json
#>
function Set-ConfigData
{
[CmdletBinding()]
param(
[Parameter(Mandatory)]
[string] $Name,
[Parameter(Mandatory)]
[object] $Value,
[switch] $Encrypt,
[int32] $JsonDepth = 2,
[string] $Path = "$env:home/myconfig.json"
)
	Set-StrictMode -Version Latest

	$object = $null
	if ( Test-Path $Path )
	{
		$object = Get-Content $path -Raw | ConvertFrom-Json
	}
	if ( -not $object )
	{
		$object = [PSCustomObject]@{}
	}

	if ( $PSVersionTable.PSVersion.Major -gt 5 -and -not $IsWindows )
	{
		$Encrypt = $false # Core 2.0 doesn't support encrypt/decrypt
	}

	if ( $Value -is 'SecureString' )
	{
		if ( $PSVersionTable.PSVersion.Major -gt 5 -and -not $IsWindows )
		{
			throw "SecureString encryption not supported in Core"
		}
		$value = ConvertTo-Json @{ "Secure-String" = (ConvertFrom-SecureString $Value) } -Compress
	}
	elseif ( $Encrypt )
	{
		$value = ConvertTo-Json @{ "Encrypted-Object" =  (ConvertFrom-SecureString (ConvertTo-SecureString (ConvertTo-Json $Value) -asplaintext -force)) } -Compress
	}
	else
	{
		$value = (ConvertTo-Json $Value -Compress -Depth $JsonDepth)
	}

	if ( -not (Get-Member -InputObject $object -Name $Name))
	{
		Add-Member -InputObject $object -Name $Name -Value $value -MemberType NoteProperty
	}
	else
	{
		$object.$name = $value.ToString()
	}
	Set-Content $path -Value (ConvertTo-Json $object)
}