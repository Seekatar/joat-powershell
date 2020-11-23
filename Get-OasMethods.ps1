<#
.SYNOPSIS
Get function objects from an OAS Yaml file

.DESCRIPTION
Creates an PSCustom object for every call.  Used as input to New-OasFunction

.EXAMPLE
$Fname = "C:\code\OktaPosh\okta_doc\api.yaml"
$yaml = ConvertFrom-Yaml (gc $Fname -raw)
$apiCalls = c:\code\joat-powershell\Get-OasMethods.ps1 -Yaml $yaml
#>
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
        $type = $parameter["type"]
        if (!$type) {
            $type = ($parameter["schema"]['$ref'] -split '/')[-1]
        }
        $params += [PSCustomObject]@{
            default = $parameter["default"]
            in = $parameter["in"]
            name = $parameter["name"]
            type = $type
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
        foreach ($methodName in $paths.$path.Keys )
        {
            $method = $yaml.paths.$path[$methodName]
            $pathObjs += @{
                path        = $path
                method      = $methodName.ToUpper()
                description = $method["description"]
                operationId = $method["operationId"]
                consumes    = $method["consumes"]
                produces    = $method["produces"]
                parameters  = makeParameters $method.parameters
                summary     = $method["summary"]
                tag         = $method["tags"] | Select-Object -First 1
                responses   = $method["responses"]
            }
        }
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
