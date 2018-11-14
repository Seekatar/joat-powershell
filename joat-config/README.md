# JOAT-Config
[![License](https://img.shields.io/badge/license-MIT-blue.svg)]()
[![PowerShell Gallery - JOAT-Config](https://img.shields.io/badge/PowerShell%20Gallery-joat--config-blue.svg)](https://www.powershellgallery.com/packages/joat-config)
[![Minimum Supported PowerShell Version](https://img.shields.io/badge/PowerShell-5.0-blue.svg)](https://github.com/PowerShell/PowerShell)

|Build, Test, Publish status |
|---|
|![Build](https://dev.azure.com/seekatar0863/JoatConfig/_apis/build/status/JoatConfig-CI)|

## Introduction
This PowerShell module has scripts for getting and setting configuration values for the current user, optionally encrypting it.  This is useful when doing automation and you need to store and retrieve configuration values to avoid hardcoding or committing to git, such as PAT, passwords, etc.

## Requirements

- Windows PowerShell 5.0 or newer.
- PowerShell Core.

## Installation
JOAT-Config is in the [PowerShell Gallery]().  To install it, execute the following command.

```powershell
Install-Module -Name joat-config
```

## Usage
The two main functions are `Get-ConfigData` and `Set-ConfigData` which basically set and get a key-value pair in a file in the user's home folder.  Help is available for all commands.  And the source has Pester tests.

For example, you can store local-specific configuration.

```powershell
Set-ConfigData my.servername -value 'host-123'

Invoke-Command {dir} -computername (Get-ConfigData my.servername)
```

Or more useful is storing encrypted data, such as PAT, APIKeys, etc.

```powershell
Set-ConfigData 'Azure.TenantId' -value 'mytenantId' -Encrypt
Set-ConfigData 'Azure.My.SubscriptionId' -value 'mysubscriptionid' -Encrypt

Connect-AzureRmAccount -TenantId (Get-ConfigData 'Azure.TenantId' -Decrypt) -Subscription (Get-ConfigData 'Azure.My.SubscriptionId' -Decrypt) -Credential (Get-Credential)
```

Objects can be stored and retrieved as well as strings.

Currently only Windows supports encrypting and decrypting of data as well as using SecureStrings.