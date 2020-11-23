param(
    [string] $folder = $env:folderToAnalyze
)
Write-Warning "Folder is $folder"

Describe 'Testing against PSSA rules' {
    Context 'PSSA Standard Rules' {
        $analysis = Invoke-ScriptAnalyzer -Path $folder -Recurse
        $scriptAnalyzerRules = Get-ScriptAnalyzerRule

        $erroractionpreference = 'stop'
        if ($analysis) {
            forEach ($rule in $scriptAnalyzerRules) {
                $test = @"
                It "Should pass $rule" {
                    If (`$analysis.RuleName -contains '$rule') {
                        `$analysis |
                            Where-Object RuleName -EQ '$rule' -outvariable failures |
                            Out-Default
                        `$failures.Count | Should -Be 0
                    }
                }
"@
                Invoke-Expression $test # lastest didn't work since $rule lost when actually run 'It'
            }
        } else {
            Write-Warning "Didn't get any analysis output from $folder $analysis"
        }
    }
} -Tags PSSA