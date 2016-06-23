<#
.Synopsis
	Create a comment block for parameters
	
.Description
	Creates a comment block for all the parameters
	to the clipboard or output

.Parameter commandName
	Name of PowerShell command

.Parameter synopsis
	synopiss to write out, defaults to '.'

.Parameter description
	description to write out, defaults to '.'

.Parameter example
	Switch to add Example

.Parameter outputs
	Ouptputs to write out

.Example
	Supplying most of the data
	
	New-Comments.ps1 .Invoke-SetupPush.ps1 -synopsis 'Run a setup push' -description 'Run the setup push from end-to-end' 

.Outputs
	Comment to clipboard

#>
[CmdletBinding()]
param(
[Parameter(Mandatory,ValueFromPipeLine)]
[string] $commandName,
[string] $synopsis='.',
[string] $description='.',
[switch] $example,
[string] $outputs,
[switch] $interactive,
[switch] $passThru,
[ValidateScript({Test-Path $_ -pathType Leaf})]
[string] $fileName
)
	begin
	{
		Add-Type -AssemblyName 'System.Windows.Forms'
		$commonParams = 'ErrorAction',
						'WarningAction',
						'Verbose',
						'Debug',
						'ErrorVariable',
						'WarningVariable',
						'OutVariable',
						'OutBuffer',
						'PipelineVariable',
						'InformationAction',
						'InformationVariable'
	}
	
	process
	{
		Set-StrictMode -Version Latest
		
		function getValue( $name, $default = '.'  )
		{
			if ( $interactive )
			{
				Read-Host -Prompt "Enter ${name}" 
			}
			else 
			{
				$default
			}
		}
		
		$str = ""
		$cmdletBindings = $null
		$cmd = Get-Command $commandName -ErrorAction Ignore	 
		if ( $cmd )
		{
			$sb = $cmd.ScriptBlock
			if ( $sb )
			{
				$attrs = $sb.Attributes
				if ( $attrs )
				{
					$cmdletBindings = $attrs | Where-Object { $_.TypeId -eq [System.Management.Automation.CmdletBindingAttribute] }
					if ( $cmdletBindings -and $cmdletBindings.SupportsShouldProcess )
					{
						$commonParams += 'WhatIf'
						$commonParams += 'Confirm'
					}
				}
			}
			else
			{
				Write-Warning "No scriptblock found for $commandName.  May not be valid."
			}
			$str = "<#
.Synopsis
	$(getValue 'synopsis' $synopsis )
	
"
	
$description = getValue 'description (optional)' $description 
if ( $description )
{
$str += ".Description
	$description

"
}
	if ( $cmd.Parameters )
	{
			foreach( $p in $cmd.Parameters.Keys )
			{
				if ( $commonParams -contains $p )
				{
					continue
				}
				$str += ".Parameter $p
	$(getvalue "help for parameter '$p'")

"	
			}
			if ( $example )
			{
				$str += ".Example
	.

"
	}
			}
$outputs = getValue 'output (optional)' $outputs 
if ( $outputs )
{
$str += ".Outputs
	$outputs

"
}
			$str += "#>
"		
			if ( $passThru )
			{
				$str
			}

			if ( $fileName )
			{
				$content = Get-Content -Path $fileName -Raw
				Set-Content -Path $fileName -Value "$str$content" 
				Write-Host "$fileName updated with comment block"
			}
			else
			{
				[Windows.Forms.Clipboard]::Clear();
				[Windows.Forms.Clipboard]::SetText( $str, [System.Windows.Forms.TextDataFormat]::Text )
				Write-Host "Output written to clipboard"
			}
			
		}
		else
		{
			Write-Warning "Command '$commandName' not found"
		}

	}

