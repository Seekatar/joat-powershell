<#
.SYNOPSIS
Join-Path with multiple paths

.PARAMETER Paths
Array of paths

.OUTPUTS
Path
#>
function Join-MultiplePaths
{
[CmdletBinding()]
param(
[Parameter(ValueFromRemainingArguments,ValueFromPipeline,Mandatory)]
[string[]] $Paths,
[switch] $ConvertPath
)

    begin 
    {
        $result = ""
    }

    process
    {
        Write-Verbose "$paths $($paths.GetType()) $($paths[0].GetType()) $($paths.count)"
        foreach ( $p in $Paths )
        {
            if ( $result )
            {
                $result = Join-Path $result $p
            }
            else 
            {
                $result = $p    
            }
            Write-Verbose "$p -- $result"
        }
    }

    end
    {
        if ( $ConvertPath )
        {
            Convert-Path $result
        }
        else
        {
            $result
        }
    }
}