<#
    V1 PowerShell SDK Tab expansion helper function to allow 
    tab expansion of asset types and their attributes
#>
$script:sortedKeys = $null
$script:debuggingTab = $false
Set-StrictMode -Version Latest

if ( -not $Function:PrevTabExpansionV1 -and $Function:TabExpansion)
{
    Rename-Item Function:\TabExpansion PrevTabExpansionV1
}

function TabExpansion( $line, $lastword )
{
    if ( -not $script:sortedKeys )
    {
        $script:sortedKeys = (Get-V1Meta -noLoad).Keys | Sort-Object
    }

    if ( -not $script:sortedKeys )
    {
        if ( $script:debuggingTab) { [System.IO.File]::AppendAllText("C:\temp\tabexpansion.txt", ">$line<`t>$lastword<`n") }

        # already have assetType and completing attributes
        if ( $line -match "-V1ass\w* +(?:-as\w+)?(\w+).*(?:-pr\w* *)?(?:\w*|, *\w*)$" )
        {
            if ( $script:debuggingTab) { [System.IO.File]::AppendAllText("C:\temp\tabexpansion.txt", "Match! $($Matches[1])`n") }

            if ( $script:sortedKeys -contains $Matches[1])
            {
            
                $lastword = $lastword -split "," | Select-Object -Last 1
                if ( $lastword )
                {
                    return (Get-V1Meta -assetType $Matches[1]).keys | Where-Object {$_ -like "$lastword*" } | Sort-Object
                }
                else
                {
                    return (Get-V1Meta -assetType $Matches[1]).keys | Sort-Object
                }        
            }
        }
        
        # complete assetType
        if ( ($line -like '*-V1*-assett* *' -or $line -match "(New|Get)-V1Asset +\w*$" ))
        {
            if ( $lastword )
            {
                return $script:sortedKeys | Where-Object {$_ -like "$lastword*" }
            }
            else
            {
                return $script:sortedKeys
            }        
        }
    }

    if ( $Function:PrevTabExpansionV1 )
    {
        PrevTabExpansionV1 $line $lastWord 
    }
}
