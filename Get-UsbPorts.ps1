[CmdletBinding()]
param(
[switch] $pressEnterToExit
)

$ports = [system.io.ports.serialport]::getportnames()
if ( -not $ports )
{
    Write-Verbose "No com ports found from GetPortNames"
}
else
{
    $ports | select @{n='Name';e={$_}} , @{n='Description';e={""}}, @{n='Source';e={"SerialPorts"}}, @{n='DeviceID';e={$_}} 
}

$ports = Get-WmiObject win32_serialport | select DeviceID, Name, Description
if ( -not $ports )
{
    Write-Verbose "No com ports found WMI"
}
else
{
    $ports
}

$m = New-Object "System.Management.ManagementScope"
$q = New-Object 'System.Management.SelectQuery' -ArgumentList "Select * from win32_serialport"
$ms = New-Object "System.Management.ManagementObjectSearcher" -ArgumentList $m,$q
$ports = $ms.get()
if ( -not $ports )
{
    Write-Verbose "No com ports found from .NET"
}
else
{
    $ports | select Name, Description, @{n='Source';e={".NET"}}, DeviceID
}


# this gets FTDI, too, seems most reliable
Get-WmiObject win32_pnpentity |  ?  { $_.caption -match "com\d" } | select Name, Description, @{n='Source';e={"PnPEntity"}}, DeviceID

if ( $pressEnterToExit )
{
    Read-Host -Prompt "`nPress enter"
}