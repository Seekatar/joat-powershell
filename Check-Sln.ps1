<#
.Synopsis
	Check a sln file for missing Content files

.Parameter slnName
	name of sln file to check	
#>
param(
[ValidateScript({ Test-Path $_ -PathType Leaf})]
[string] $slnName='Camelot.sln'
)
Set-StrictMode -Version Latest

$slnName = Convert-Path $slnName

Push-Location (Split-Path $slnName -Parent)
try
{
	$projs = Select-String "\.csproj" $slnName | ForEach-Object { if ( $_  -match "([^`"]*\.csproj)") { $matches[0] }  }

	foreach ( $p in $projs )
	{
		$count = 0
		Write-Output "Checking $p..."
		$x = [xml](Get-Content (Convert-Path $p))

		Push-Location (Split-Path $p -Parent )

		try
		{
			$nsmgr = New-Object System.Xml.XmlNamespaceManager -ArgumentList $x.NameTable
			$nsmgr.AddNamespace('a','http://schemas.microsoft.com/developer/msbuild/2003')
			$x.SelectNodes("//a:Content",$nsmgr) | ForEach-Object { $f = $_.Include; if ( -not (Test-Path $f )) { $count++; Write-Warning "Missing content file `"$f`"" } } 
			
			if ( $count -eq 0 )
			{
				Write-Output "ok"
			}
		}
		finally
		{
			Pop-Location
		}
	}
}
finally
{
	Pop-Location
}