class Link
{
    [ValidateNotNullOrEmpty()]
    [string] $Name
    [ValidateNotNull()]
    [ScriptBlock] $ScriptBlock
    [ValidateSet("setup", "normal", "onError","onExit")]
    [string] $WhenToRun = "normal"
    [ValidateSet("throw", "prompt", "continue")]
    [string] $OnError = "throw"
    [object[]] $Parameters
    [string] $OutputName
    [bool] $PromptOnStep = $true
    [bool] $PromptOnError = $true
}

class Chain
{
    [ValidateNotNullOrEmpty()]
    [string] $Name
    [string] $Description
    [Link[]] $Links
}

$script:type = "setup"
$script:chain = New-Object Chain

function Get-Chain
{
    return $script:chain
}

function next
{
[CmdletBinding()]
param(
[Parameter(Mandatory)]
[string] $name,
[Parameter(Mandatory)]
[ScriptBlock] $sb,
[string] $OutputName)
    Write-Verbose "Next block $name of type $script:type"
    $link = New-Object Link
    $link.Name = $name
    $link.ScriptBlock = $sb
    $link.OutputName = $OutputName
    $link.WhenToRun = $script:type
    $script:chain.Links += $link
}

function onSetup
{
[CmdletBinding()]
param([ScriptBlock] $sb)
Set-StrictMode -Version Latest

    $script:type = "setup"
    Invoke-Command -ScriptBlock $sb
}
function onRun
{
[CmdletBinding()]
param([ScriptBlock] $sb)
Set-StrictMode -Version Latest

    $script:type = "normal"
    Invoke-Command -ScriptBlock $sb
}
function onError
{
[CmdletBinding()]
param([ScriptBlock] $sb)
Set-StrictMode -Version Latest

    $script:type = "onError"
    Invoke-Command -ScriptBlock $sb
}
function onExit
{
[CmdletBinding()]
param([ScriptBlock] $sb)
Set-StrictMode -Version Latest

    $script:type = "onExit"
    Invoke-Command -ScriptBlock $sb
}

<#
.Synopsis
    Run a chain of script blocks
#>
function Invoke-Chain
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Chain] $Chain,
        [string] $SkipUntil,
        [string] $SkipAfter,
        [switch] $Step,
        [switch] $NeverPrompt,
        [hashtable] $Parameters
    )

    Set-StrictMode -Version Latest

    $context = new-object System.Collections.Generic.List[PSVariable]
    $current = $null
    $script:alreadyWarnedSkip = $false

    ###############################################################################
    # helper to run a script
    # return 0 if run ok, 1 if error -1 if skipped
    function runScript( $script )
    {
        if ( $SkipUntil )
        {
            Write-LogMessage Verbose "SkipUntil is $SkipUntil"
        }

        if ( -not $script.NeverPrompt -and $SkipUntil )
        {
            if ( $script.Name -eq $SkipUntil -or $id -eq $SkipUntil )
            {
                $script:SkipUntil = ""
                if ( $skipAfter )
                {
                    $skipAfter = $false
                    return 0
                }
            }
            else
            {
                if ( -not $script:alreadyWarnedSkip )
                {
                    Write-LogMessage Warning "Skipping `"$($script.name)`" until $SkipUntil"
                    $script:alreadyWarnedSkip = $true
                }
                return -1
            }
        }

        if ( $WhatIfPreference)
        {
            Write-LogMessage Info "Whatif skipping running of '$($script.name)'"
            return 0
        }
        elseif ( $script.NeverPrompt -or (askYn "Execute script `"$($script.name)`"" $script.desc) )
        {
            if ( $script.NeverPrompt )
            {
                Write-LogMessage Info "**********************************************************************************"
                Write-LogMessage Info "* Running script $($script.name)... (never prompts)"
                Write-LogMessage Info "**********************************************************************************"
            }
            if ( $script.echoScript )
            {
                Write-LogMessage Debug $script.script
            }

            $Error.Clear()
            $Global:LASTEXITCODE = 0
            $nl = [Environment]::NewLine
            try
            {
                Set-LoggerSource $id
                #$result = @(Invoke-Expression $("`$(" + $script.script + ")|Write-LogMessage -level Info"))
                $result = @($script.ScriptBlock.InvokeWithContext($null, $context, $Parameters))

                if ( $script.OutputName )
                {
                    New-Variable -Name $script.OutputName -Value $$result
                    $context.Add((Get-Variable -Name $script.OutputName))
                }
            }
            catch
            {
                $errMsg = "Exception running `"$($script.name)`"${nl}$_${nl}$($_.ScriptStackTrace)${nl}"
                $errMsg += "${nl}Script:${nl}"
                $lineNo = 1
                foreach ( $l in $script.script -split "`n")
                {
                    $errMsg += ("{0:0000} {1}$nl" -f $lineNO++, $l)
                }
                Write-LogMessage Error $errMsg
                throw $_
            }
            finally
            {
                Set-LoggerSource ""
            }
            $ret = $LASTEXITCODE

            if ( $result.Count -gt 1 )
            {
                $result[0..$($result.Count - 2)] | Write-LogMessage -level Info
            }

            if ( $ret -ne 0 -or $Error )
            {
                $errMsg = "Error running `"$($script.name)`" with last exit code of $ret and `$Error of $([bool]$Error)"
                if ( $Error )
                {
                    $errMsg += ($error | Select-Object -uniq) | ForEach-Object { "`n>>>> Error >>>>${nl}$($_.toString())${nl}$($_.ScriptStackTrace)${nl}" }
                }
                $errMsg += "${nl}Script:${nl}"
                $lineNo = 1
                foreach ( $l in $script.script -split "`n")
                {
                    $errMsg += ("{0:0000} {1}$nl" -f $lineNO++, $l)
                }
                Write-LogMessage Warning $errMsg

                if ( $script.promptOnError )
                {
                    $answer = Select-Prompt -prompt "Errors. Do you want to continue?" -defaultValue "&no" -values "&yes|continue", "&no|stop the deploy"
                    if ( $answer -eq "&no" )
                    {
                        return 1
                    }
                }
                else
                {
                    return 1
                }
            }
            if ( $script.Name -eq $StepAfter -or $id -eq $StepAfter )
            {
                $script:StepAfter = ""
                Set-AskYnStep -value $true
            }
            return 0
        }
        else
        {
            return -1 # skipped
        }
    }

    $script:timings = @()
    $script:current = ""

    function runChain([Chain] $Chain,
        [string] $SkipUntil,
        [string] $SkipAfter,
        [switch] $Step,
        [switch] $NeverPrompt,
        [hashtable] $Parameters
    )
    {
        $i = 0
        foreach ( $link in $Chain )
        {
            $start = [DatetimeOffset]::Now
            $i++
            Write-Progress -Activity $activity -Status "Step $i of $count" -CurrentOperation $script.Name -PercentComplete $(100 * ($i / ($Count)))
            $current = $link
            $ret = runLink $link

            if ( $ret -eq -1 ) #skipped
            {
                $script:timings += New-Object PSObject -Property @{ Name = $script.Name; Duration = 0; State = "skipped" }
            }
            elseif ( $ret -eq 0 ) #ok
            {
                $script:timings += New-Object PSObject -Property @{ Name = $script.Name; Duration = $([DatetimeOffset]::Now - $start).TotalSeconds; State = "OK" }
            }
            else
            {
                return 1
            }
            $script:current = ""
        }
    }
    function _formatTimingDuration($timing)
    {
        $width = 7
        if ( $timing.State -ne "OK" )
        {
            $timing.State
        }
        elseif ( $timing.Duration -ge 60 )
        {
            "{0,${width}:f2} mins" -f ($timing.Duration/60)
        }
        else
        {
            "{0,${width}:f2} secs" -f $timing.Duration
        }
    }

    Write-Verbose "Running Chain $($Chain.Name)"
    Write-Verbose "SkipAfter is $SkipAfter"
    Write-Verbose "SkipAfter is $SkipAfter"
    Write-Verbose "Step is $Step"

    $setup = @($Chain | Where-Object WhenToRun -eq "setup")
    $normal = @($Chain | Where-Object WhenToRun -eq "normal")

    $activity = "Running chain $($Chain.Name)"
    $count = $setup.Count + $normal.Count
    try
    {
        Write-Progress -Activity $activity -Status "Starting..."
        runChain -Chain $setup -Step:$step -NeverPrompt:$NeverPrompt -Parameters $Parameters
        runChain -Chain $normal -SkipUntil $SkipUntil -SkipAfter $SkipAfter -Step:$step -NeverPrompt:$NeverPrompt -Parameters $Parameters
    }
    catch
    {
        runChain -Chain ($Chain | Where-Object WhenToRun -eq "onError") -Parameters @{Error = $_}
    }
    Write-Progress -Activity $activity -Completed

}