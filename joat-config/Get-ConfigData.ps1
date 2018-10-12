<#
.SYNOPSIS
Get data from a JSON config file

.PARAMETER Path
Path to the config file

.PARAMETER Name
Name of the config data to get

.PARAMETER AsSecureString
Return the encrypted data as a SecureString

.PARAMETER Decrypt
Return encrypted data in clear text

.PARAMETER NoWarnIfNotFound
Don't kick out a Warning message if not found

.EXAMPLE
An example

.OUTPUTS
Object from config file, or $null
#>
function Get-ConfigData
{
[CmdletBinding()]
param(
[Parameter(Mandatory)]
[string] $Name,
[switch] $AsSecureString,
[switch] $Decrypt,
[switch] $NoWarnIfNotFound,
[string] $Path = "$env:home/myconfig.json"
)
	Set-StrictMode -Version Latest

	if ( -not (Test-Path $Path -PathType Leaf))
	{
		throw "Path $Path not found"
	}

	$object = Get-Content $path -Raw | ConvertFrom-Json
	if ( Get-Member -InputObject $object -Name $Name)
	{
		$value = $object.$Name
		if ( $PSVersionTable.PSVersion.Major -gt 5 -and -not $IsWindows )
		{
			$decryptedtString = $false  # Core 2.0 doesn't support encrypt/decrypt
			if ( $AsSecureString )
			{
				Write-Warning "AsSecureString not supported in PS Core"
				return ""
			}
		}

		$value = ConvertFrom-Json $value
		$isSecureString = [bool](Get-Member -InputObject $value -Name "Secure-String" -MemberType NoteProperty )
		$isEncryptedObject = [bool](Get-Member -InputObject $value -Name "Encrypted-Object" -MemberType NoteProperty )
		Write-Verbose "isSecureString = $isSecureString isEncryptedObject = $isEncryptedObject"
		if ( $isSecureString -or $isEncryptedObject)
		{
			if ( $isEncryptedObject )
			{
				$value = $value."Encrypted-Object"
			}
			else
			{
				$value = $value."Secure-String"
			}
			Write-Verbose "Value is $value"
			$secureString = $value | ConvertTo-SecureString

			if ( $Decrypt )
			{
				$decryptedtString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))
				if ( $isEncryptedObject )
				{
					ConvertFrom-Json $decryptedtString
				}
				else
				{
					$decryptedtString
				}
			}
			else
			{
				$secureString
			}
		}
		else
		{
			$value
		}
	}
	elseif ( -not $NoWarnIfNotFound )
	{
		Write-Warning "Didn't find value named $name in $path"
	}
}