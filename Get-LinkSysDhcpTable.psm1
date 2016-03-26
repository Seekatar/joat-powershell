$script:cred = $null

<#
.Synopsis 
    Get the DHCP table by hitting the Gateway IP, and parse the LinkSys Output

.Parameter cred
    optional credential, if not supplied will prompt

.Outputs
    Objects with Name, IpAddress, MacAddress
#>
function Get-LinkSysDhcpTable
{
    [CmdletBinding()]
    param([PSCredential] $cred)

    if ( $cred )
    {
        $script:cred = $cred
    }

    Set-StrictMode -Version Latest

    $myGateway = (Get-NetIPConfiguration).IPv4DefaultGateway[0].NextHop
    if ( -not $myGateway )
    {
        Write-Error "Didn't get gateway IP"
        return
    }

    Write-Verbose "Gateway is $myGateway"
    if ( -not $script:cred )
    {
        $script:cred = Get-Credential -UserName admin -Message "Enter password for LinkSys Router at $myGateway"
    }
    $x = Invoke-WebRequest -Uri "http://$myGateway/DHCPTable.htm" -Credential $script:cred

    [ValidateSet('looking','nextName','nextIp','nextMac')]
    $state = 'looking'

    $names = @()

    foreach ( $l in ($x.Content -split "`n") )
    {
        if ( $l -like "*bgcolor=cccccc*" )
        {
            $state = 'nextName'
        }
        elseif ( $state -eq 'nextName' )
        {
            if ( $l -match "<td>(.+)\s+</td>" )
            {
                $name = $Matches[1]
                $state = 'nextIp'
            }
            else
            {
                Write-Error "Didn't get name"
            }
        }
        elseif ( $state -eq 'nextIp' )
        {
            if ( $l -match "<td>([\d\.]+)" )
            {
                $ip = $Matches[1]
                $state = 'nextMac'
            }
            else
            {
                Write-Error "Didn't get ip for $name"
            }
        }
        elseif ( $state -eq 'nextMac' )
        {
            if ( $l -match "<td>([a-f0-9:]+)")
            {
                $mac = $Matches[1]
                $state = 'looking'
                Write-Verbose "Found all parts for $name"
                [PSCustomObject]@{Name=$name;IpAddress=$ip;MacAddress=$mac}
            }
            else
            {
                Write-Error "Didn't get mac for $name"
            }
        }
    }
}