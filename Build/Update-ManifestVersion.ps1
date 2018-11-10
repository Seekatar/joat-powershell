<#
.SYNOPSIS
Helper script to set the version of a Manifest

.PARAMETER ManifestPath
The path to the existing psd1 file

.PARAMETER Revision
Revision number.  Must be supplied

.PARAMETER Build
Build number.  If not supplied, used the one in the manifest

.PARAMETER Minor
Minor version number.  If not supplied, used the one in the manifest

.PARAMETER Major
Major version number.  If not supplied, used the one in the manifest

.EXAMPLE
..\Build\Update-ManifestVersion.ps1 .\joat-config.psd1 1

#>
[CmdletBinding(SupportsShouldProcess)]
param(
[ValidateScript({Test-Path $_ -PathType Leaf})]
[Parameter(Mandatory)]
[string] $ManifestPath,
[Parameter(Mandatory)]
[int] $Revision,
[int] $Build = -1,
[int] $Minor = -1,
[int] $Major = -1
)
    Set-StrictMode -Version Latest

    $manifest = Test-ModuleManifest -Path $ManifestPath -Verbose:$false

    if ( $Build -eq -1 )
    {
        $Build = $manifest.Version.Build
    }
    if ( $Minor -eq -1 )
    {
        $Minor = $manifest.Version.Minor
    }
    if ( $Major -eq -1 )
    {
        $Major = $manifest.Version.Major
    }
    $newVersion = "{0}.{1}.{2}.{3}" -f $Major,$Minor,$Build,$Revision

    if ( $PSCmdlet.ShouldProcess($ManifestPath,"Set module version to $newVersion"))
    {
        Update-ModuleManifest -Path $ManifestPath -ModuleVersion $newVersion
    }
