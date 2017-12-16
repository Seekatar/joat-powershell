
<#
.SYNOPSIS
Invoke an AWS command, retrying if get rate error from AWS due to frequent calls

.NOTES
Calls Test-AwsCredential to verify the command can run

.PARAMETER ScriptBlock
The command to execute, if you need parameters, pass in Args, and use $args[] in the script

.PARAMETER Args
Any parameters to pass to ScriptBlock

.EXAMPLE
Invoke-AwsPaced { Get-CGIPUserPoolClientList -UserPoolId $args[0] }  $pool.Id

.EXAMPLE
Invoke-AwsPaced { Get-CGIPUserList -UserPoolId $args[0] } $pool.Id

.EXAMPLE
$userPool = Invoke-AwsPaced {Get-CGIPUserPool -UserPoolId $args[0]} -arg $_.id

.OUTPUTS
The outputs from the command
#>
function Invoke-AwsPaced
{
[CmdletBinding()]
param(
[ScriptBlock] $ScriptBlock, 
[object[]] $Args,
[switch] $SkipTest,
[int] $MaxTries = 20 )

    Set-StrictMode -Version Latest
    . (Join-Path $PSScriptRoot Test-AwsCredential.ps1)

    if ( -not $SkipTest )
    {
        Test-AwsCredential
    }

    # exponential backoff per https://aws.amazon.com/blogs/ses/how-to-handle-a-throttling-maximum-sending-rate-exceeded-error/
    function getSleepDuration([int] $currentTry, [long] $minSleepMillis = 10, [long] $maxSleepMillis = 5000)
    {
        $currentTry = [Math]::max(0, $currentTry)
        $currentSleepMillis = $minSleepMillis * [Math]::pow(2, $currentTry)
        [Math]::min($currentSleepMillis, $maxSleepMillis)
    }

    for ( $i = 0; $i -lt $MaxTries; $i++ )
    {
        try
        {
            $ret = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Args
            return $ret
        }
        catch
        {
            if ( $_.Exception.Message -eq "Rate exceeded" )
            {
                $sleep =  (getSleepDuration $i)
                Write-Verbose "Sleeping for $sleep since got rate warning"
                Start-Sleep -Milliseconds $sleep
            }
            else
            {
                throw $_
            }
        }
    }
    throw "Max tries ($MaxTries) exceeded"
}
