[CmdletBinding()]
param (
    [Parameter(Mandatory,ParameterSetName="FName")]
    [ValidateScript( {Test-Path $_ -PathType Leaf})]
    [string] $Fname = 'C:\code\OktaPosh\okta_doc\api.yaml',
    [Parameter(Mandatory,ParameterSetName="Yaml")]
    [HashTable] $Yaml
)
function makeParameters
{
    [CmdletBinding()]
    param(
        [array] $Parameters
    )
    Set-StrictMode -Version Latest

    $params = @()
    foreach ($parameter in $Parameters )
    {
        $params += [PSCustomObject]@{
            default = $parameter["default"]
            in = $parameter["in"]
            name = $parameter["name"]
            type = $parameter["type"]
            description = $parameter["description"]
            required = $parameter["required"] ?? $false
        }
    }
    $params
}

function makePaths
{
    [CmdletBinding()]
    param(
        [hashtable] $paths
    )

    Set-StrictMode -Version Latest

    $pathObjs = @()
    foreach ($path in $paths.Keys )
    {
        foreach ($methodName in $yaml.paths.$path.Keys )
        {
            $method = $yaml.paths.$path[$methodName]
            $pathObj = @{
                path        = $path
                method      = $methodName.ToUpper()
                description = $method["description"]
                consumes    = $method["consumes"]
                produces    = $method["produces"]
                parameters  = makeParameters $method.parameters
                summary     = $method["summary"]
                tags        = $method["tags"]
            }
        }
        $pathObjs += $pathObj
    }
    $pathObjs
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module powershell-yaml
if (!$yaml) {
    Write-Verbose "Converting Yaml..."
    $yaml = ConvertFrom-Yaml (Get-Content $Fname -raw)
}

makePaths $yaml.paths
