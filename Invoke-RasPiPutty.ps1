[CmdletBinding()]
param(
[string] $ComputerName,
[string] $user = "pi"
)

Import-Module (Join-Path $PSScriptRoot Get-LinkSysDhcpTable.psm1)
Import-Module (Join-Path $PSScriptRoot cliMenu.psm1)

while ( $true )
{
	$active = [ordered]@{}

	Write-Verbose "Checking LinkSys"
	$computers  = @(Get-LinkSysDhcpTable)
	Write-Verbose "Checking $($computers.Count) computers"
	$computers  | Sort-Object name |  ForEach-Object { if ( $_.Name -like '*pi*' -and (Test-Connection -ComputerName $_.IpAddress -Count 1 -ErrorAction Ignore)) 
											{
												$active["{0,-20}{1,-17}{2}" -f $_.Name,$_.IpAddress,$_.MacAddress] = $_.IpAddress
											} }

	$active["  "] = ''
	$active["  > Refresh"] = 'r'
	$active["  > Exit"] = 'x'

	while ( $true )
	{
		if ( -not $active )
		{
			Write-Warning "Didn't find any computers on LinkSys"
		}
		else 
		{
			$choice = $active | Show-Menu -Title "Pick host to SSH into" 
			if ( $choice -eq "x" )
			{
				return
			}
			elseif ( $choice -eq "r" )
			{
				break
			}
			elseif ( $choice )
			{
				Write-Verbose "Choice is $choice"
				C:\code\putty.exe -ssh "$user@$($choice)"
			}
		}
	}
}
