
foreach( $i in (Get-ChildItem (Join-Path $PSScriptRoot "Config\*.ps1") -File -Exclude *.tests.ps1 -Recurse) )
{
    . $i
}

Export-ModuleMember -Function "*-*"