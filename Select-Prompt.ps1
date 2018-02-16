<#
.Synopsis
	Prompt the user by listing some choices

.Description
	.

.Parameter prompt
	Prompt to display for the user

.Parameter defaultValue
	One of the values, or empty if there is not default

.Parameter values
	two or more values for the user to select from.  They will be prefixed by a number.  Use | to append help string

.Example
	Select-Prompt "My prompt" "test" "test" "test2" "test3"

	Prompts with a default value of test

.Example
	Select-Prompt "My prompt" "test2" "test|help1" "test2|help2" "test3|no help"

	Prompts with a default value of test2, showing help.  If enter is pressed test2 is returned

.Example
	Select-Prompt "My prompt" "&No" "&Yes|You will do it!" "&No|You won't do it"

	Will return &No or &Yes

.Example
    $prompts = "&Yes|You will do it!","&No|You won't do it"
    Select-Prompt "My prompt" "&No" @prompts

    Builds the list of prompts as an array

.Outputs
	the values[] item selected by the user
#>
function Select-Prompt
{
	[CmdletBinding()]
	param(
	[Parameter(Mandatory)]
	[string] $prompt,
	[Parameter(Mandatory)]
	[string] $defaultValue,
	[Parameter(Mandatory,ValueFromRemainingArguments)]
	[String[]] $values
	)
	$i = 1
	$name = @()
	$choices = $values | ForEach-Object {
		$x = @($_.Split("|"))
		$name += $x[0]
		if ( -not $x[0].Contains("&") )
		{
			$x[0] = "&$i - $($x[0])"
		}
		New-Object 'System.Management.Automation.Host.ChoiceDescription' -ArgumentList $x
		$i++
		}
	$selection =[System.Management.Automation.Host.ChoiceDescription[]] $choices
	$defaultNo = $name.IndexOf($defaultValue)
	$i = 0
	Write-Verbose "Select prompt default is $defaultNo values of $($values | ForEach-Object {"'$_' ($i)";$i++})"
	if ( $env:SelectPromptNeverPrompt )
	{
		Write-Warning "`$env:SelectPromptNeverPrompt auto-answering '$prompt' with '$defaultValue'"
		$choice = $defaultNo
	}
	else
	{
		$choice = $host.ui.PromptForChoice($prompt,"",$selection,$defaultNo)
	}
	Write-Verbose "Selection was $choice"

	if ( $choice -lt 0 )
	{
		return $null
	}
	else
	{
		return $name[$choice]
	}
}
