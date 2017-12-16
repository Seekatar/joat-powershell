
foreach( $i in (Get-ChildItem (Join-Path $PSScriptRoot "Aws\*.ps1") -File -Exclude *.tests.ps1 -Recurse) )
{
    . $i
}

Export-ModuleMember -Function "*-*"