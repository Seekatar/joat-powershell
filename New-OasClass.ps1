$classes = @{}

<#
.SYNOPSIS
Short description

.DESCRIPTION
Long description

.PARAMETER Definitions
Parameter description

.EXAMPLE
New-oasclass  $yaml['definitions']

.NOTES
General notes
#>
function New-OasClass
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Hashtable] $Definitions
    )

    process
    {
        foreach ($def in $Definitions.Keys)
        {
            $class = @{
                name       = $def
                properties = @()
            }
            Write-Verbose $def
            if ($Definitions.$def['properties'])
            {
                foreach ($propName in $Definitions.$def.properties.Keys | Where-Object { $_ -notlike '_*' -and $_ -notlike 'x-*'})
                {
                    $prop = $Definitions.$def.properties.$propName
                    if ($prop['$ref'])
                    {
                        $class.properties += [PSCustomObject]@{
                            Name = $propName
                            type = ($prop['$ref'] -split '/')[-1]
                        }
                    }
                    else
                    {
                        $class.properties += [PSCustomObject]@{
                            Name     = $propName
                            type     = $prop['type']
                            readOnly = $prop['readOnly'] ?? $false
                            format   = $prop['format']
                        }
                    }
                }
                $classes[$def] = [PSCustomObject]$class
            }
            else
            {
                Write-Information "Skipping $def since no properties" -InformationAction Continue
            }
        }
        Write-Information "Loaded $($classes.keys.Count) classes" -InformationAction Continue

    }

}

function Get-OasClass
{
    [CmdletBinding()]
    param(
        [string] $ClassName
    )
    Set-StrictMode -Version Latest

    if ($ClassName) {
        $classes[($ClassName -split '/')[-1]]
    } else {
        $classes.Keys
    }
}
