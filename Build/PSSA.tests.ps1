param(
$folder = "..\Public"
)
Write-Warning "Folder is $folder"

Describe 'Testing against PSSA rules' {
    Context 'PSSA Standard Rules' {
        $analysis = Invoke-ScriptAnalyzer -Path $folder -Recurse
        $scriptAnalyzerRules = Get-ScriptAnalyzerRule

        forEach ($rule in $scriptAnalyzerRules) {
            It "Should pass $rule" {
                If ($analysis -and $analysis.RuleName -contains $rule) {
                    $analysis |
                        Where-Object RuleName -EQ $rule -outvariable failures |
                        Out-Default
                    $failures.Count | Should Be 0
                }
            }
        }
    }
} -Tags PSSA