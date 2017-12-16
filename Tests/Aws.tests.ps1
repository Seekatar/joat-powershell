. (Join-Path $PSScriptRoot "..\Aws\Invoke-AwsPaced.ps1")

Describe "AwsTests" {

    It "pacedFail" {
        try {
            Invoke-AwsPaced -script { throw "Rate Exceeded" } -SkipTest -MaxTries 5
            $false | Should be $true
        }
        catch {

        }
    }

    $global:failTest = 0
    function paceFn
    {
        $global:failTest += 1
        if ( $global:failTest -lt $args[0]  )
        {
            throw "Rate Exceeded"
        }
        $global:failTest
    }

    It "paced" {
        $global:failTest = 0
        Invoke-AwsPaced -script { paceFn $args[0] } -Args 5 -SkipTest | Should be 5
    }
}