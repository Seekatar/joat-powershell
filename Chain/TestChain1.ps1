[CmdletBinding()]
param()

onSetup {
    next "Log start message" {
        logMsg ("=" * 80)
        $msg = "Starting point releases `"{0}`" -Analytics `"{1}`" -DataMart `"{2}`"" -f ($Lifecycle -join "`",`""), ($Analytics -join "`",`""), ($DataMart -join "`",`"")
        logMsg $msgSend-ReleaseStatus -Icon Start -Text $msg
    }
    next "Check credential" {
        if ( $Credential )
        {
            $script:credentials = $Credential
        }
        elseif ( -not $script:credentials)
        {
            Get-CorpCredential
        }
    }
    next "Test accesses" {
        $driveName = Test-FilesBuilds $RootPath

        Test-AwsCredential
    } -OutputName "driveName"
    next "Copy Folders Update MakeX" {
        Copy-ReleaseFolder -Lifecycle $Lifecycle -RootPath $RootPath
        Update-MakeXFile -Lifecycle $Lifecycle -MakeXPath $MakeXPath -Analytics $Analytics -DataMart $DataMart
    }
}

onRun {
    next "Send Release Build" {
        Send-ReleaseBuild -Lifecycle $Lifecycle
        Wait-ReleaseJob "build"
    }

    next "Upload to Hostess" {
        Write-Information "Uploading to Hostess..."
        Send-Hostess -Lifecycle $Lifecycle -Analytics $Analytics -DataMart $DataMart -RootPath $RootPath

        Update-CoreGitHub -Lifecycle $Lifecycle -GitHubUser $GitHubUser -GitHubToken $GitHubToken -CtmConfigName $CtmConfigName
    }

    next "AWS upload" {
        Invoke-AwsUpload -Lifecycle $Lifecycle
    }

    next "Update progression" {
        Update-CtmProgression -Lifecycle $Lifecycle -PhaseName "Published" -CtmConfigName $CtmConfigName
    }

    next "Test Hostess" {
        Test-HostessPage -Lifecycle $Lifecycle -DataMart $DataMart -Analytics $Analytics
    }

    next "Test Release Zip" {
        Test-ReleaseZip -Lifecycle $Lifecycle -DataMart $DataMart -Analytics $Analytics
    }

    next "Complete" {
        Send-ReleaseStatus -Icon Stop -Text "Release complete.  Check <https://versionone2013.hostpilot.com/Support/Wiki/Current%20Products.aspx>"
        "https://versionone2013.hostpilot.com/Support/Wiki/Current%20Products.aspx"
    }
}

onError {
    next "Error" {
        Send-ReleaseStatus -Icon Failed -Text "Error in Release $_`n$($_.ScriptStackTrace)"
        Write-Warning "Didn't execute the following steps:`n$($steps[$step..($steps.count-1)] -join "`n")"
        Write-Error "Error $_`n$($_.ScriptStackTrace)"
    }
}

onExit {
    next "Cleanup" {
        $ErrorActionPreference = $prevErrorPref
        $InformationPreference = $prevInformationPref
    }
}
