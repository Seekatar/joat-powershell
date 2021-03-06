Set-StrictMode -Version Latest
<#
	Robert Martin's cliMenu.psm1

	See help for functions exported from the module for details on usage
#>

$Script:BoxChars =[PSCustomObject]@{
   'HorizontalDouble'            = ([char]9552).ToString()
   'VerticalDouble'              = ([char]9553).ToString()
   'TopLeftDouble'               = ([char]9556).ToString()
   'TopRightDouble'              = ([char]9559).ToString()
   'BottomLeftDouble'            = ([char]9562).ToString()
   'BottomRightDouble'           = ([char]9565).ToString()
   'HorizontalDoubleSingleDown'  = ([char]9572).ToString()
   'HorizontalDoubleSingleUp'    = ([char]9575).ToString()
   'Horizontal'                  = ([char]9472).ToString()
   'Vertical'                    = ([char]9474).ToString()
   'TopLeft'                     = ([char]9484).ToString()
   'TopRight'                    = ([char]9488).ToString()
   'BottomLeft'                  = ([char]9492).ToString()
   'BottomRight'                 = ([char]9496).ToString()
   'Cross'                       = ([char]9532).ToString()
   'VerticalDoubleRightSingle'   = ([char]9567).ToString()
   'VerticalDoubleLeftSingle'    = ([char]9570).ToString()
}

[int]$Script:OptionIndent = 5
Function WriteLine
{
    Param([string]$message
        , [int]$Column = $Host.UI.RawUI.CursorPosition.X
        , [int]$Row = $Host.UI.RawUI.CursorPosition.Y
        , [switch]$InvertColors
        , [switch]$NoNewLine
    )
    
    [console]::SetCursorPosition($Column, $Row)
    if($InvertColors) { Write-Host $message -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor -NoNewline:$NoNewLine}
    else { Write-Host $message -NoNewline:$NoNewLine}
}

Filter TruncateLine ([string[]]$message, [int]$length = $Host.UI.RawUI.WindowSize.Width)
{
    If($length -lt 0) { $length += $Host.UI.RawUI.WindowSize.Width }
    ForEach($m in $message)
    {
        If($m.length -le $length){ Write-Output $m }
        Else { Write-Output ("{0}..." -f $m.Substring(0,($length-3))) }
    }
}

Function DisplayMenu($Title, $Description, $CurrentPage = 1, $PageCount = 1, $PageOptions)
{
    Clear-Host
    
    If($Title)
    {
		$Titles = @($Title -split "[`r]{0,1}`n")
        $Titles = TruncateLine -message $Titles -length -8
		$maxLen = ($Titles | Measure-Object -Property Length -Maximum).Maximum
        WriteLine -Message ($Script:BoxChars.TopLeft+$Script:BoxChars.Horizontal* ($maxLen  + 2)+$Script:BoxChars.TopRight) -Column 3
		foreach ( $t in $titles )
		{
			WriteLine -Message ("$($Script:BoxChars.Vertical) {0,-$maxLen} $($Script:BoxChars.Vertical)" -f $t) -Column 3
		}
        WriteLine -Message ($Script:BoxChars.BottomLeft+$Script:BoxChars.Horizontal* ($maxLen  + 2)+$Script:BoxChars.BottomRight) -Column 3

        Write-Host
    }
    Else { Write-Host }
    
    If($Description)
    {
        $Description = TruncateLine -message $Description -length -2
        $Description | ForEach-Object { WriteLine -message $_ -Column 2 }
        Write-Host
    }

    If($PageCount -gt 1)
    {
        WriteLine -message "Page $CurrentPage of $PageCount" -Column ($Script:OptionIndent + 2)
        Write-Host
    }

    For($i = 0; $i -lt $PageOptions.count; $i ++)
    {
        $key = TruncateLine $PageOptions[$i].key -length (-1 * ($Script:OptionIndent  + 2))

        If($PageOptions[$i].Checked) { WriteLine "+" -NoNewline -Column ($Script:OptionIndent - 2) }
        If($i -eq 0) { WriteLine -message $key -InvertColors -Column $Script:OptionIndent}
        Else { WriteLine -message $key -Column $Script:OptionIndent }
    }
}

<#
.Synopsis
    CommandLine Menu

.Description
    Shows a graphical menu on the commandline.

    INPUTS::
    List of Strings (StringOptions)
    HashTable (HashTableOptions) ("Key" gets displayed and "Value" gets returned)
    InputObjects (Pipe Objects to menu, use PipelineKey & PipelineValue to determine
                    which properties of the objects are used to populate the menu)

    CONTROLS::
    Up/Down Arrows to change which item is selected.
    Right/Left Arrows to change which page is selected.
    Enter to return option(s).
    Space to check an option.

.Parameter Title
    Title to be displayed on menu.

.Parameter Description
    Text to be displayed below the Title

.Parameter MultiSelect
    Allows multiple options to be selected and deslected
    using the spacebar.

.Parameter Foreground
    The foreground color for the menu

.Parameter Background
    The background color for the menu

.Parameter HashTableOptions
    Ordered hashtable containining the key/value pairs.
    Key will get displayed on the menu.
    Value will get returned.

.Parameter StringOptions
    Array of strings used to populate the menu.
    Displayed string will get returned.

.Parameter InputObjects
    Array of objects, use PipelineKey and PipelineValue to
    determine which properties of the object are use for the menu.

.Parameter PipelineKey
    Used with "InputObjects", determines which property
    on the object will be displayed on the menu.

.Parameter PipelineValue
    Used with "InputObjects", determines which property
    on the object will be returned from the menu.

.Parameter dontClearOnClose
	Don't clear the screen when closing the menu.  Use when cascading menus
	on the non-last menu

.Parameter dontResetOnOpen
    Don't reset the screen when opening.  Use when cascading menus
	on the non-first menu
	 
.Example
    "Bob","Mary","Jack" | Show-Menu -Title "Which name do you want?"
    Demonstrates how to use a list of strings on the pipeline.

.Example
    Show-Menu -Title "Which name do you want?" -StringOptions "Bob","Mary","Jack"
    Demonstrates how to pass in a list of strings.

.Example
    @{"Bob(10)"=10;"Mary(15)"=15;"Jack(20)"=20} | Show-Menu -Title "Which age do you want?"
    Demonstrates how to use a hashtable on the pipeline.

.Example
    Show-Menu -Title "Which age do you want?" -HashTableOptions @{"Bob(10)"=10;"Mary(15)"=15;"Jack(20)"=20}
    Demonstrates how to pass in a hashtable.

.Example
    Get-ChildItem -File | Show-Menu -Title "Which file do you want?" -PipelineKey Name -PipelineValue FullName
    Demonstrates how to use objects on the pipeline.

.Example 
    Show-Menu -Title "Which file do you want?" -PipelineKey Name -PipelineValue FullName -InputObjects (Get-ChildItem -File)
    Demonstrates how to pass in objects.

.Example
    Get-ChildItem -File | Show-Menu -Title "Which files do you want?" -PipelineKey Name -PipelineValue FullName -MultiSelect
    Demonstrates how to use the MultiSelect option.

.Example 
    $p = @{"Bob(10)"=10;"Mary(15)"=15;"Jack(20)"=20} | Show-Menu -Title "Which age do you want?" -dontClearOnClose
	$c = "Red","Blue","Green" | Show-Menu -Title "Which color?" -dontClearOnClose -dontResetOnOpen
	$m = Read-Host "Enter your mother's maiden name"
	$a = "Pig","Horse","Cow","Monkey" | Show-Menu -Title "Which animal?" -dontResetOnOpen
	$p,$c,$m,$a

	Demonstrates using cascading menus 
#>

Function Show-Menu
{
    [cmdletbinding(DefaultParameterSetName="string")]
    Param([string]$Title
        , [string[]]$Description
        , [Parameter(Mandatory,ValueFromPipeline,ParameterSetName="Hashtable")]$HashTableOptions
        , [Parameter(ParameterSetName="Hashtable")][Switch]$InvertKeyValue
        , [Parameter(Mandatory,ValueFromPipeline,ParameterSetName="string")]
            [string[]]$StringOptions
        , [Parameter(Mandatory,ParameterSetName="pipeline")]
            [string]$PipelineKey
        , [Parameter(Mandatory,ParameterSetName="pipeline")]
            [string]$PipelineValue
        , [Parameter(Mandatory,ValueFromPipeline,ParameterSetName="pipeline")]$InputObjects
        , [System.ConsoleColor]$Foreground
        , [System.ConsoleColor]$Background
        , [switch]$MultiSelect
		, [switch]$dontClearOnClose
		, [switch]$dontResetOnOpen
    )
    
    Begin
    {
        [System.Console]::TreatControlCAsInput = $true

		if ( -not $dontResetOnOpen )
		{
			$script:Backup = [PSCustomObject]@{
					ForegroundColor = $Host.UI.RawUI.ForegroundColor
					BackgroundColor = $Host.UI.RawUI.BackgroundColor
					CursorSize = $Host.UI.RawUI.CursorSize
					CursorPosition = $Host.UI.RawUI.CursorPosition
					BufferSize = $Host.UI.RawUI.BufferSize
					WindowSize = $Host.UI.RawUI.WindowSize
					Buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle 0, 0, $Host.UI.RawUI.BufferSize.Width, $Host.UI.RawUI.BufferSize.Height))
				}
		}
        If($Foreground) { $Host.UI.RawUI.ForegroundColor = $Foreground }
        If($Background) { $Host.UI.RawUI.BackgroundColor = $Background }
        
        $Host.UI.RawUI.CursorSize = 0
        $Options = @()
        $results = @()
    }

    Process
    {
        Switch($PSCmdlet.ParameterSetName)
        {
            "Hashtable"
            {
                ForEach($hto in $HashTableOptions)
                {
                    If($InvertKeyValue) { $hto.Keys | ForEach-Object { $Options += [PSCustomObject]@{Key=$hto[$_];Value=$_;Checked=$false} } }
                    Else { $hto.Keys | ForEach-Object { $Options += [PSCustomObject]@{Key=$_;Value=$hto[$_];Checked=$false} } }
                }
            }

            "string"
            {
                $StringOptions | ForEach-Object { $Options += [PSCustomObject]@{Key=$_;Value=$_;Checked=$false} }
            }

            "pipeline"
            {
                $InputObjects | ForEach-Object { $Options += [PSCustomObject]@{Key=$_.$PipelineKey;Value=$_.$PipelineValue;Checked=$false} }
            }
        }
    }

    End
    {
        New-Variable -Name theError
        Try
        {
            [int]$ItemsPerPage = $host.ui.RawUI.WindowSize.Height -2
            If($Title) 
			{ 
				$count = @($Title -split "[`r]{0,1}`n").count
				$ItemsPerPage -= (2+$count)
			}
            If($Description) { $ItemsPerPage -= (@($Description).count + 1) }
            If($Options.count -gt $ItemsPerPage) { $ItemsPerPage -= 2 }

            $PageCount = [math]::Truncate(($Options.count -1)/ $ItemsPerPage) + 1
            [int]$CurrentItem = 0
            [int]$StartRow = $Host.UI.RawUI.WindowSize.Height - $ItemsPerPage - 1
            [int]$CurrentRow = 0
            
            DisplayMenu -Title $title -Description $Description -CurrentPage ([math]::Truncate($CurrentItem / $ItemsPerPage) + 1) -PageCount $PageCount -PageOptions $Options[0..([Math]::Min($options.Count,$ItemsPerPage)-1)]
            
            [boolean]$isChoosing = $true
            While($isChoosing)
            {
                Switch([System.Console]::ReadKey($true).Key)
                {
                
                    "DownArrow"
                    {
                        WriteLine -message $Options[$CurrentItem].Key -Column $Script:OptionIndent -Row ($StartRow + $CurrentRow)

                        $CurrentItem += 1
                        If($CurrentItem % $ItemsPerPage -eq 0 -or $CurrentItem -ge $Options.count)
                        {
                            $CurrentItem -= ($CurrentRow + 1)
                            $CurrentRow = 0
                        }
                        Else { $CurrentRow += 1}

                        WriteLine -message $Options[$CurrentItem].Key -Column $Script:OptionIndent -Row ($StartRow + $CurrentRow) -InvertColors
                    }
                    
                    "UpArrow"
                    {
                        WriteLine -message $Options[$CurrentItem].Key -Column $Script:OptionIndent -Row ($StartRow + $CurrentRow)
                                                
                        If($CurrentItem % $ItemsPerPage -eq 0 -or $CurrentItem -eq 0)
                        {
                            If($CurrentItem + ($ItemsPerPage - 1) -ge $Options.count)
                            {
                                $CurrentItem = $Options.count - 1
                                $CurrentRow = $CurrentItem % $ItemsPerPage
                            }
                            Else
                            {
                                $CurrentItem += ($ItemsPerPage - 1)
                                $CurrentRow += ($ItemsPerPage - 1)
                            }
                        }
                        Else
                        {
                            $CurrentItem -= 1 
                            $CurrentRow -= 1
                        }

                        WriteLine -message $Options[$CurrentItem].Key -Column $Script:OptionIndent -Row ($StartRow + $CurrentRow) -InvertColors
                    }

                    {$_ -eq "RightArrow" -or $_  -eq "PageDown"}
                    {
                        If($Options.count -gt $ItemsPerPage)
                        {
                            #If(($options.count - $CurrentItem) -lt $ItemsPerPage) { $CurrentItem = 0 }
                            If($CurrentItem - $CurrentRow + $ItemsPerPage -ge $Options.count) { $CurrentItem = 0 }
                            Else
                            { 
                                $CurrentItem -= $CurrentRow
                                $CurrentItem += $ItemsPerPage
                            }

                            $CurrentRow = 0
                            $CurrentPage = [math]::Truncate($CurrentItem / $ItemsPerPage) + 1

                            DisplayMenu -Title $title -Description $Description -CurrentPage $CurrentPage -PageCount $PageCount -PageOptions $Options[$CurrentItem..([Math]::Min($options.Count,$CurrentPage*$ItemsPerPage)-1)]
                        }
                    }

                    {$_  -eq "LeftArrow" -or $_  -eq "PageUp"}
                    {
                        If($Options.count -gt $ItemsPerPage)
                        {
                            If(($CurrentItem - $ItemsPerPage) -ge 0)
                            {
                                $CurrentItem -= $CurrentRow
                                $CurrentItem -= $ItemsPerPage
                            }
                            Else { $CurrentItem = ($PageCount - 1) * $ItemsPerPage }

                            $CurrentRow = 0
                            $CurrentPage = [math]::Truncate($CurrentItem / $ItemsPerPage) + 1

                            DisplayMenu -Title $title -Description $Description -CurrentPage $CurrentPage -PageCount $PageCount -PageOptions $Options[$CurrentItem..([Math]::Min($options.Count,$CurrentPage*$ItemsPerPage)-1)]
                        }
                    }
                                     
                    "Enter"
                    {
                        $isChoosing = $false
                        If(-not $MultiSelect) { $results = @($Options[$CurrentItem].Value) }
                        Else
                        {
                            $results = @($Options | Where-Object {$_.Checked} | Select-Object -ExpandProperty Value)
                        }
                    }

                    "Escape"
                    {
                        $isChoosing = $false
                    }
                    
                    "Spacebar"
                    {
                        If($MultiSelect)
                        {
                            If($Options[$CurrentItem].checked)
                            {
                                $Options[$CurrentItem].checked = $false
                                WriteLine -message " " -Column ($Script:OptionIndent - 2) -Row ($StartRow + $CurrentRow)
                            }
                            Else
                            {
                                $Options[$CurrentItem].checked = $true
                                WriteLine -message "+" -Column ($Script:OptionIndent - 2) -Row ($StartRow + $CurrentRow)
                            }
                        }
                    }
                    
                    "F1" { Get-Help about_cliMenu_Controls -ShowWindow }

                    default {}
                }
            }
        }
        Catch
        {
            $theError = $_
        }
        Finally
        {
			$Host.UI.RawUI.CursorSize = $Script:Backup.CursorSize
			if ( -not $dontClearOnClose )
			{
				$Host.UI.RawUI.ForegroundColor = $Script:Backup.ForegroundColor
				$Host.UI.RawUI.BackgroundColor = $Script:Backup.BackgroundColor
				$Host.UI.RawUI.SetBufferContents((New-Object System.Management.Automation.Host.Coordinates 0, 0), $Script:Backup.Buffer)
				$Host.UI.RawUI.CursorPosition = $Script:Backup.CursorPosition
				$Script:Backup = $null

				[System.Console]::TreatControlCAsInput = $false
			}

            If($theError) { Write-Host ($theError | out-string ) -ForegroundColor Red }
            If($results.count -gt 0) { $results | Write-Output }
        }
    }
}    


<#
.Synopsis
    CommandLine Input

.Description
    Shows a graphical input box on the commandline.
    Input box is centered in the screen.

.Parameter Title
    Title to be displayed on input box.

.Parameter Description
    Text to be displayed inside the input box.

.Parameter Width
    Determines how large of an input box to create.

.Parameter Foreground
    The foreground color for the input box.

.Parameter Background
    The background color for the input box.

.Parameter Reset
    If your colors have been messed up by this command, use this
    switch to revert them back.

.Example
    Read-Input -Title "What is your name?"
    
.Example
    Read-Input -Title "What is your age?" -Description "Your physical, not emotional age."

#>
Function Read-Input
{
    [cmdletBinding()]
    Param([string]$Title
        , [string[]]$Description
        , [int]$Width = 65
        , [System.ConsoleColor]$Foreground
        , [System.ConsoleColor]$Background
        , [switch]$Reset)

    #BEGIN
    If($Script:Backup -and $Reset)
    {
        $Host.UI.RawUI.ForegroundColor = $Script:Backup.ForegroundColor
        $Host.UI.RawUI.BackgroundColor = $Script:Backup.BackgroundColor
        $Host.UI.RawUI.SetBufferContents((New-Object System.Management.Automation.Host.Coordinates 0, 0), $Script:Backup.Buffer)
        $Host.UI.RawUI.CursorPosition = $Script:Backup.CursorPosition
        $Script:Backup = $null
    }
    Else
        {
        [System.Console]::TreatControlCAsInput = $true
        If(-not $Script:Backup)
        {
            $script:Backup = [PSCustomObject]@{
                    ForegroundColor = $Host.UI.RawUI.ForegroundColor
                    BackgroundColor = $Host.UI.RawUI.BackgroundColor
                    CursorPosition = $Host.UI.RawUI.CursorPosition
                    Buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle 0, 0, $Host.UI.RawUI.BufferSize.Width, $Host.UI.RawUI.BufferSize.Height))
                }
        }
        Clear-Host

        If($Foreground) { $Host.UI.RawUI.ForegroundColor = $Foreground }
        Else { $Host.UI.RawUI.ForegroundColor = $script:Backup.BackgroundColor }
        If($Background) { $Host.UI.RawUI.BackgroundColor = $Background }
        Else { $Host.UI.RawUI.BackgroundColor = $script:Backup.ForegroundColor }
    
        #Process

        If($Host.UI.RawUI.WindowSize.Width -lt $Width) { $Width = $Host.UI.RawUI.WindowSize.Width }
        $Left = ($Host.UI.RawUI.WindowSize.Width - $width) / 2
        $Top = ($Host.UI.RawUI.WindowSize.Height - 3 - $Description.count) / 2
    
        Write-Verbose $Title
        If(-not $Title) { $msg = "{0}{1}{2}" -f $BoxChars.TopLeftDouble, ($BoxChars.HorizontalDouble * ($width - 2)), $BoxChars.TopRightDouble }
        Else { $msg = "{0}{1}{2}{3}{4}" -f $BoxChars.TopLeftDouble, ($BoxChars.HorizontalDouble * 3), (TruncateLine -message $Title -length ($Width - 4)), ($BoxChars.HorizontalDouble * ($width - 5 - $title.Length)), $BoxChars.TopRightDouble }

        WriteLine -Column $Left -Row $Top -message $msg

        If($Description)
        {
            ForEach($d in $Description)
            {
                WriteLine -Column $Left -message ("{0}{1}{2}{3}" -f $BoxChars.VerticalDouble, (TruncateLine -message $d -length ($Width -2)), (" " * ($width - 2 - $d.Length)), $BoxChars.VerticalDouble)
            }
            WriteLine -Column $Left -message ("{0}{1}{2}" -f $BoxChars.VerticalDoubleRightSingle, ($BoxChars.Horizontal * ($width-2)), $BoxChars.VerticalDoubleLeftSingle)
        }

        WriteLine -Column $Left -message ("{0}>{1}<{2}" -f $BoxChars.VerticalDouble, (" " * ($width - 4)), $BoxChars.VerticalDouble)
        WriteLine -Column $Left -message ("{0}{1}{2}" -f $BoxChars.BottomLeftDouble, ($BoxChars.HorizontalDouble * ($width - 2)), $BoxChars.BottomRightDouble)
    
        WriteLine -Column ($left + 3) -Row ($Host.UI.RawUI.CursorPosition.y - 2) -NoNewLine
        Read-Host | Write-Output

        #END
        $Host.UI.RawUI.ForegroundColor = $Script:Backup.ForegroundColor
        $Host.UI.RawUI.BackgroundColor = $Script:Backup.BackgroundColor
        $Host.UI.RawUI.SetBufferContents((New-Object System.Management.Automation.Host.Coordinates 0, 0), $Script:Backup.Buffer)
        $Host.UI.RawUI.CursorPosition = $Script:Backup.CursorPosition
        $Script:Backup = $null

        [System.Console]::TreatControlCAsInput = $false
    }
}


Export-ModuleMember -Function Show-Menu, Read-Input