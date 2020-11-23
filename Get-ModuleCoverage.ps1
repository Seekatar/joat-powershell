<#
.SYNOPSIS
Find functions not called in *.tests.ps1 files
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({Get-Module $_})]
    [string] $ModuleName,
    [ValidateScript({Test-Path $_ -PathType Container})]
    [Parameter(Mandatory)]
    [string] $TestFolder
)

Set-StrictMode -Version Latest

$fns = @{}
Get-Command -Module $ModuleName -CommandType Function, Script, Cmdlet | ForEach-Object { $fns[$_.Name] = 0 }
if (!$fns) {
    Write-Warning "No function found in module $ModuleName"
    return
}

Write-Verbose "Checking files"
Get-ChildItem $TestFolder\*.tests.ps1 -r  | ForEach-Object {
    $code = Get-Content $_

    Write-Verbose "    $_"
    [System.Management.Automation.PSParser]::Tokenize($code,[ref]$null) |
        Where-Object Type -eq 'Command' |
        ForEach-Object {
            if ($fns[$_.Content] -ne $null) {
                $fns[$_.Content] += 1
            }
        }
}

$missingCount = 0
$total = $fns.Keys.Count
$missing = @($fns.GetEnumerator() | Where-Object Value -eq 0)
if ($missing) {
    "Missing function calls:"
    $missing.Key | Sort-Object | ForEach-Object {"  $_"}
    $missingCount = $missing.Count
}
"Total: $total Missing: $missingCount Coverage: $([int](100*($total-$missingCount)/$total))%"