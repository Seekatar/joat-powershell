<#
.SYNOPSIS
Get a list of github repo's SSH URLs
#>
param
(
[string] $url = "https://api.github.com/orgs/klwine/repos"
[string] $apiToken = (Get-ConfigData KLWines.Github -Decrypt)
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(Invoke-RestMethod -ur $url -h @{"Authorization"="token $token"} ) |  ForEach-Object { "git clone $($_.ssh_url)" }