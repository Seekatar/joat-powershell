
<#
.SYNOPSIS
Run a PSScriptAnalyzer test

.PARAMETER PSSATestScriptPath
Folder where the Pester tests live, will execute all with the tags specified

.PARAMETER PSSATestScriptPath
Path the the PSSA Test file

.PARAMETER Tags
Test tags, defaults to PSSA, UnitTest (PS Script Analyzer)

.EXAMPLE
..\Build\Invoke-ScriptAnalyzerTest.ps1 -FolderToAnalyze .

.EXAMPLE
.\Invoke-ScriptAnalyzerTest.ps1 -ModulePath $env:Build_SourcesDirectory

As called from AzureDevOps Build pipeline
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string] $FolderToAnalyze,
    [string] $OutputPath = (Join-Path $FolderToAnalyze 'TEST-PesterResults.xml'),
    [string[]] $Tags = @("PSSA")
)

    Set-StrictMode -Version Latest

    Write-Verbose "Testing Folder $FolderToAnalyze.  Output to $OutputPath"

    if ( $PSVersionTable.PSVersion -lt "5.1")
    {
        $PSVersionTable
        throw "Must have PS 5.1 or higher to use Module cmdlets with Credentials"
    }

    $scriptAnalyzerRules = Get-ScriptAnalyzerRule
    $testFile = "$(New-TemporaryFile).ps1"
    Set-Content -Path $testFile -Encoding ascii -Value @"
Describe 'Testing against PSSA rules' {
    Context 'PSSA Standard Rules' {
        `$analysis = Invoke-ScriptAnalyzer -Path '$FolderToAnalyze' -Recurse

        `$ErrorActionPreference = 'stop'
        if (`$analysis) {
"@

    forEach ($rule in $scriptAnalyzerRules) {
        Add-Content -Path $testFile -Encoding ascii -Value  @"
                `$test = "'It Should pass $rule' { `
                    If (`$analysis.RuleName -contains '$rule') { `
                        `$analysis |`
                             Where-Object RuleName -EQ '$rule' -outvariable failures |`
                            Out-Default`
                        `$failures.Count | Should -Be 0`
                    }`
                }"`
                Invoke-Expression `$test
"@
    }

    Add-Content -Path $testFile -Encoding ascii -Value  @"
        } else {
            Write-Warning "Didn't get any analysis output from `$FolderToAnalyze `$analysis"
        }
    }
} -Tags PSSA
"@

$PSSATestScriptPath = $testFile
$testFile
return

# if (!(Get-PackageProvider nuget)) {
#     Install-PackageProvider -Name Nuget -Scope CurrentUser -Force -Confirm:$false | out-null
# }
if ( -not (Get-Module -Name Pester ) ) {
    Install-Module -Name Pester -Scope CurrentUser -Force -Confirm:$false -SkipPublisherCheck
}
S} else {
    Write-Verbose "PSScriptAnalyzer Installed"
}

Import-Module Pester
Import-Module PSScriptAnalyzer

# no longer pass parameters to script?
$env:folderToAnalyze = $FolderToAnalyze

$result = Invoke-Pester -Path $PSSATestScriptPath -OutputFile $OutputPath -OutputFormat 'NUnitXml' -Tags $tags -PassThru

$result.Tests | Select @{n="Ok";e={if ($_.Result -ne 'Passed') {'[-]'}else {'[+]'}}},Name | Sort Ok -Desc | Format-Table -Auto
if ( $result.FailedCount )
{
    throw "Pester tests failed.  Count is $($result.FailedCount)"
}

