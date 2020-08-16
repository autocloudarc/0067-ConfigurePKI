﻿#requires -version 5.1
#requires -RunAsAdministrator

using Namespace System
using Namespace System.Net # for IP addresses
Using Namespace System.Runtime.InteropServices # # For Azure AD service principals marshal clas
Using Namespace Microsoft.Azure.Commands.Management.Storage.Models # for Azure storage
Using Namespace Microsoft.Azure.Commands.Network.Models # for Azure network resources
<#
.SYNOPSIS
Configure a PKI server on an existing VM in Azure.


.DESCRIPTION
This sript will configure an Active Directory Certificate Services on an existing Windows Server 2019 Server in Azure.

PRE-REQUISITES:
1. Before executing this script, ensure that you change the directory to the directory where the script is located. For example, if the script is in: c:\scripts\Deploy-AzResourceGroup.ps1 then
    change to this directory using the following command:
    Set-Location -Path c:\scripts

.PARAMETER includeUbuntu
Inclue an Ubuntu server for this deployment.

.EXAMPLE
.\Deploy-AzResourceGroup.ps1 -excludeWeb yes -excludeSql yes -excludeAds yes -excludePki yes -includeUbuntu yes -Verbose

.INPUTS
None

.OUTPUTS
The outputs generated from this script includes:
1. A transcript log file to provide the full details of script execution. It will use the name format: Deploy-AzureResourceGroup-TRANSCRIPT-<Date-Time>.log

.NOTES
LEGAL DISCLAIMER:
This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. 
THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. 
We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree:
(i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded;
(ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and
(iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees, that arise or result from the use or distribution of the Sample Code.
This posting is provided "AS IS" with no warranties, and confers no rights.

.LINK
1. https://gist.github.com/chrisbrownie/f20cb4508975fb7fb5da145d3d38024a

.COMPONENT
PKI, Active Directory Certificate Services, Desired State Configuration, Azure Infrastructure, PowerShell, Azure Automation

.ROLE
Automation Engineer
DevOps Engineer
Azure Engineer
Azure Administrator
Azure Architect

.FUNCTIONALITY
Deploys an Azure automation lab infrastructure

#>

[CmdletBinding()]
param
(
) # end param

$BeginTimer = Get-Date -Verbose

#region MODULES
# Module repository setup and configuration
$PSModuleRepository = "PSGallery"
Set-PSRepository -Name $PSModuleRepository -InstallationPolicy Trusted -Verbose
Install-PackageProvider -Name Nuget -ForceBootstrap -Force

# Bootstrap dependent modules
$ARMDeployModule = "ARMDeploy"
if (Get-InstalledModule -Name $ARMDeployModule -ErrorAction SilentlyContinue)
{
    # If module exists, update it
    [string]$currentVersionADM = (Find-Module -Name $ARMDeployModule -Repository $PSModuleRepository).Version
    [string]$installedVersionADM = (Get-InstalledModule -Name $ARMDeployModule).Version
    If ($currentVersionADM -ne $installedVersionADM)
    {
            # Update modules if required
            Update-Module -Name $ARMDeployModule -Force -ErrorAction SilentlyContinue -Verbose
    } # end if
} # end if
# If the modules aren't already loaded, install and import it.
else
{
    Install-Module -Name $ARMDeployModule -Repository $PSModuleRepository -Force -Verbose
} #end If
Import-Module -Name $ARMDeployModule -Verbose
#endregion MODULES

#region Environment setup
# Use TLS 1.2 to support Nuget provider
Write-Output "Configuring security protocol to use TLS 1.2 for Nuget support when installing modules." -Verbose
[ServicePointManager]::SecurityProtocol = [SecurityProtocolType]::Tls12
#endregion

#region FUNCTIONS

function New-ARMDeployTranscript
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPrefix
    ) # end param

    # Get curent date and time
    $TimeStamp = (get-date -format u).Substring(0, 16)
    $TimeStamp = $TimeStamp.Replace(" ", "-")
    $TimeStamp = $TimeStamp.Replace(":", "")

    # Construct transcript file full path
    $TranscriptFile = "$LogPrefix-TRANSCRIPT" + "-" + $TimeStamp + ".log"
    $script:Transcript = Join-Path -Path $LogDirectory -ChildPath $TranscriptFile

    # Create log and transcript files
    New-Item -Path $Transcript -ItemType File -ErrorAction SilentlyContinue
} # end function

function Get-PSGalleryModule
{
	[CmdletBinding(PositionalBinding = $false)]
	Param
	(
		# Required modules
		[Parameter(Mandatory = $true,
				   HelpMessage = "Please enter the PowerShellGallery.com modules required for this script",
				   ValueFromPipeline = $true,
				   Position = 0)]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string[]]$ModulesToInstall
	) #end param

    # NOTE: The newest version of the PowerShellGet module can be found at: https://github.com/PowerShell/PowerShellGet/releases
    # 1. Always ensure that you have the latest version

	$Repository = "PSGallery"
	Set-PSRepository -Name $Repository -InstallationPolicy Trusted
	Install-PackageProvider -Name Nuget -ForceBootstrap -Force
	foreach ($Module in $ModulesToInstall)
	{
        # If module exists, update it
        If (Get-InstalledModule -Name $Module -ErrorAction SilentlyContinue)
        {
            # To avoid multiple versions of a module is installed on the same system, first uninstall any previously installed and loaded versions if they exist
            Update-Module -Name $Module -Force -ErrorAction SilentlyContinue -Verbose
        } #end if
		    # If the modules aren't already loaded, install and import it
		else
		{
			# https://www.powershellgallery.com/packages/WriteToLogs
			Install-Module -Name $Module -Repository $Repository -Force -ErrorAction SilentlyContinue -AllowClobber -Verbose
			Import-Module -Name $Module -ErrorAction SilentlyContinue -Verbose
		} #end If
	} #end foreach
} #end function

# TASK-ITEM: Customize funciton
function Get-GitHubRepoFiles
{
<#
    Original function inspired by and credit goes to Chris Brown. Thank you Chris! Source: https://gist.github.com/chrisbrownie/f20cb4508975fb7fb5da145d3d38024a
#>
Param
(
    [string]$repoOwner,
    [string]$repoName,
    [string]$repoPath,
    [string]$fileToDownload,
    [string]$targetPath
) # end param

    $baseUri = "https://api.github.com/"
    $uriArgs = "repos/$repoOwner/$repoName/contents/$repoPath"
    $uri = $baseUri+$uriArgs
    $webRequest = Invoke-WebRequest -Uri $uri
    $objects = $webRequest.Content | ConvertFrom-Json
    $desiredFile = $objects | Where-Object {$_.name -eq $fileToDownload} | Select-Object -Property -exp download_url

    if (-not (Test-Path $targetPath))
    {
        # Destination path does not exist, let's create it
        try
        {
            New-Item -Path $targetPath -ItemType Directory -ErrorAction Stop
        } # end try
        catch
        {
            throw "Could not create path '$targetPath'!"
        } # end catch
    } # end if

    $fileDestination = Join-Path $targetPath (Split-Path $desiredFile -Leaf)
    try
    {
        Invoke-WebRequest -Uri $desiredFile -OutFile $fileDestination -ErrorAction Stop -Verbose
        "Retrieved '$($desiredFile)' to '$fileDestination'"
    } # end try
    catch
    {
        throw "Unable to download '$($desiredFile.path)'"
    } # end catch
} # end function

#endregion FUNCTIONS

#region TRANSCRIPT
[string]$Transcript = $null
$scriptName = $MyInvocation.MyCommand.name
# Use script filename without exension as a log prefix
$LogPrefix = $scriptName.Split(".")[0]
$modulePath = "$env:systemdrive\Program Files\WindowsPowerShell\Modules"

$LogDirectory = Join-Path $modulePath -ChildPath $LogPrefix -Verbose
# Create log directory if not already present
If (-not(Test-Path -Path $LogDirectory -ErrorAction SilentlyContinue))
{
    New-Item -Path $LogDirectory -ItemType Directory -Verbose
} # end if

# funciton: Create log files for transcript
New-ARMDeployTranscript -LogDirectory $LogDirectory -LogPrefix $LogPrefix -Verbose

Start-Transcript -Path $Transcript -IncludeInvocationHeader -Verbose
#endregion TRANSCRIPT

#region HEADER
$label = "AUTOCLOUDARC PROJECT 0067: CONFIGURE PKI SERVER"
$headerCharCount = 200
# function: Create new header
$header = New-ARMDeployHeader -label $label -charCount $headerCharCount -Verbose

Write-Output $header.SeparatorDouble  -Verbose
Write-Output $Header.Title  -Verbose
Write-Output $header.SeparatorSingle  -Verbose
#endregion HEADER

#region PATH
# Set script path
Write-Output "Changing path to script directory..." -Verbose
Set-Location -Path $PSScriptRoot -Verbose
Write-Output "Current directory has been changed to script root: $PSScriptRoot" -Verbose
#endregion PATH

#region Prompt for modules upgrade
[string]$proceed = $null
Write-Output ""
$proceed = Read-Host -Prompt @"
The AzureRM modules will be removed and replaced with the Az modules.
For details and instructions why and how to upgrade to the Az modules, see https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-3.3.0.
OK to proceed ['Y' or 'YES' to continue | 'N' or 'NO' to exit]?
"@
if ($proceed -eq "N" -OR $proceed -eq "NO")
{
    Write-Output "Deployment terminated by user. Exiting..."
    PAUSE
    EXIT
} #end if ne Y
elseif ($proceed -eq "Y" -OR $proceed -eq "YES")
{
[string]$azurePreferredModule = "Az"
[string]$azureNonPreferredModule = "AzureRM"
# https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-1.1.0
Remove-ARMDeployPSModule -ModuleToRemove $azureNonPreferredModule -Verbose
# Get required PowerShellGallery.com modules.
Get-ARMDeployPSModule -ModulesToInstall $azurePreferredModule -PSRepository $PSModuleRepository -Verbose
#endregion

#region Athenticate to Subscription
Write-Output "Your browser authentication prompt for your subscription may be opened in the background. Please resize this window to see it and log in."
# Clear any possible cached credentials for other subscriptions
Clear-AzContext
Connect-AzAccount -Environment AzureCloud -Verbose

Do
{
    (Get-AzSubscription).Name
	[string]$Subscription = Read-Host "Please enter your subscription name, i.e. [MySubscriptionName] "
	$Subscription = $Subscription.ToUpper()
} #end Do
Until ($Subscription -in (Get-AzSubscription).Name)
Select-AzSubscription -SubscriptionName $Subscription -Verbose
#endregion

#region Retrieve Configuration

#endregion

#region Upload Configuration
#endregion

#region Compile Configuration
#endregion

#region Onboard VM
#endregion

#region Apply Configuration
#endregion

#region Report Configuration
#endregion

#region Test Configuration
#endregion

#region Display Summary
$StopTimer = Get-Date -Verbose
Write-Output "Calculating elapsed time..."
$ExecutionTime = New-TimeSpan -Start $BeginTimer -End $StopTimer
$Footer = "TOTAL SCRIPT EXECUTION TIME: $ExecutionTime"
Write-Output ""
Write-Output $Footer
#endregion

} # end else if

#region Cleanup Resources
# Resource group and log files cleanup messages
$labResourceGroupFilter = "rg??"
Write-Warning "The list of PoC resource groups are:"
Get-AzResourceGroup -Name $labResourceGroupFilter -Verbose
Write-Output ""
Write-Warning "To remove the resource groups, use the command below:"
Write-Warning 'Get-AzResourceGroup -Name <YourResourceGroupName> | ForEach-Object { Remove-AzResourceGroup -ResourceGroupName $_.ResourceGroupName -Verbose -Force }'

Write-Warning "Transcript logs are hosted in the directory: $LogDirectory to allow access for multiple users on this machine for diagnostic or auditing purposes."
Write-Warning "To examine, archive or remove old log files to recover storage space, run this command to open the log files location: Start-Process -FilePath $LogDirectory"
Write-Warning "You may change the value of the `$modulePath variable in this script, currently at: $modulePath to a common file server hosted share if you prefer, i.e. \\<server.domain.com>\<share>\<log-directory>"
#endregion

Stop-Transcript -Verbose

#region OPEN-TRANSCRIPT
# Create prompt and response objects for continuing script and opening logs.
$openTranscriptPrompt = "Would you like to open the transcript log now ? [YES/NO]"
Do
{
    $openTranscriptResponse = read-host $openTranscriptPrompt
    $openTranscriptResponse = $openTranscriptResponse.ToUpper()
} # end do
Until ($openTranscriptResponse -eq "Y" -OR $openTranscriptResponse -eq "YES" -OR $openTranscriptResponse -eq "N" -OR $openTranscriptResponse -eq "NO")

# Exit if user does not want to continue
If ($openTranscriptResponse -in 'Y', 'YES')
{
    Start-Process -FilePath notepad.exe $Transcript -Verbose
} #end condition
else
{
    # Terminate script
    Write-Output "End of Script!"
    $header.SeparatorDouble
} # end else
#endregion