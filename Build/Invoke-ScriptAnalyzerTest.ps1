
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
..\Build\Invoke-ScriptAnalyzerTest.ps1 -PSSATestScriptPath ..\Build\PSSA.tests.ps1 -FolderToAnalyze .

.EXAMPLE
.\Invoke-ScriptAnalyzerTest.ps1 -PSSATestScriptPath $env:Build_SourcesDirectory\BuildHelpers\PSSA.tests.ps1 -ModulePath $env:Build_SourcesDirectory

As called from AzureDevOps Build pipeline
#>
[CmdletBinding()]
param(
[Parameter(Mandatory)]
[ValidateScript({Test-Path $_ -PathType Leaf})]
[string] $PSSATestScriptPath,
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

Install-PackageProvider -Name Nuget -Scope CurrentUser -Force -Confirm:$false | out-null
if ( -not (Get-Module -Name Pester ) )
{
    Install-Module -Name Pester -Scope CurrentUser -Force -Confirm:$false -SkipPublisherCheck
}
if ( -not (Get-Module -Name PSScriptAnalyzer ) )
{
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -Confirm:$false -SkipPublisherCheck
}

Import-Module Pester
Import-Module PSScriptAnalyzer

$result = Invoke-Pester -Script @{ Path="$PSSATestScriptPath";Parameters=@{folder="$FolderToAnalyze"}} -OutputFile $OutputPath -OutputFormat 'NUnitXml' -Tags $tags -PassThru
if ( $result.FailedCount )
{
    throw "Pester tests failed.  Count is $($result.FailedCount)"
}

