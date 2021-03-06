﻿#requires -version 5.1
#requires -RunAsAdministrator

using Namespace System
using Namespace System.Net # for IP addresses
Using Namespace System.Runtime.InteropServices # # For Azure AD service principals marshal class
Using Namespace Microsoft.Azure.Commands.Management.Storage.Models # for Azure storage
Using Namespace Microsoft.Azure.Commands.Network.Models # for Azure network resources
<#
.SYNOPSIS
Configure a PKI server on an existing VM in Azure.


.DESCRIPTION
This sript will configure an Active Directory Certificate Services on an existing Windows Server 2019 Server in Azure.

PRE-REQUISITES:
1. Before executing this script, ensure that you change the directory to the directory where the script is located. For example, if the script is in: c:\scripts\Script.ps1 then
    change to this directory using the following command:
    Set-Location -Path c:\scripts

.EXAMPLE
. .\Configure-PKIonVMinAzure.ps1 -rgpName <rgpName> -aaaName <aaaName> -Verbose

.INPUTS
None

.OUTPUTS
The outputs generated from this script includes:
1. A transcript log file to provide the full details of script execution. It will use the name format: <ScriptName>-TRANSCRIPT-<Date-Time>.log

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
1. https://docs.microsoft.com/en-us/azure/automation/automation-dsc-compile#:~:text=%20Compile%20a%20DSC%20configuration%20in%20Azure%20State,parameters.%20Parameter%20declaration%20in%20DSC%20configurations%2C...%20More%20

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

#region 02.00 Execute script
[CmdletBinding()]
param
(
    [string]$repoOwner = "autocloudarc",
    [string]$repoName = "0067-ConfigurePKI",
    [string]$repoBranch = "master",
    [string]$sourceDirectory = "dsc",
    [string]$configurationFile = "PkiConfig.ps1",
    [string]$configDataFile = "PkiConfigData.psd1",
    [string[]]$filesToDownload = @($configurationFile,$configDataFile),
    [string]$configName = "PkiConfig",
    [string]$aaaName = "aaa-1c5dce57-10",
    [string]$rgpName = "rg11",
    [string[]]$modulesForAzureAutomation = @("Az.Accounts","Az.Automation","ActiveDirectoryCSDsc","CertificateDsc","xPendingReboot","xStorage"),
    [string]$PSModuleRepository = "PSGallery",
    [string]$domainAdminCred = 'domainAdminCred'
) # end param

$BeginTimer = Get-Date -Verbose

#region MODULES
# Module repository setup and configuration
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

# TASK-ITEM: Add function to ARMDeploy module
function Get-GitHubRepositoryFile
{
<#
.Synopsis
   Download selected files from a Github repository to a local directory or share
.DESCRIPTION
   This function downloads a specified set of files from a Github repository to a local drive or share, which can include a *.zipped file
.EXAMPLE
   Get-GithubRepositoryFiles -Owner <Owner> -Repository <Repository> -Branch <Branch> -Files <Files[]> -DownloadTargetDirectory <DownloadTargetDirectory>
.NOTES
    Author: Preston K. Parsard; https://github.com/autocloudarc
    Ispired by: Josh Rickard;
        1. https://github.com/MSAdministrator
        2. https://raw.githubusercontent.com/MSAdministrator/GetGithubRepository
    REQUIREMENTS:
    1. The repository from which the script artifacts are downloaded must be public to avoid  authentication
.LINK
    http://windowsitpro.com/powershell/use-net-webclient-class-powershell-scripts-access-web-data
    http://windowsitpro.com/site-files/windowsitpro.com/files/archive/windowsitpro.com/content/content/99043/listing_03.txt
#>
    [CmdletBinding()]
    Param
    (
        # Please provide the repository owner
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        # Please provide the name of the repository
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$Repository,

        # Please provide a branch to download from
        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$Branch,

        # Please provide a folder in GitHub where the file is located.
        [string]$Directory,

        # Please provide the list of files to download
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Files,

        # Please provide a local target path for the GitHub files and folders
        [Parameter(Mandatory=$true,
                   Position=4,
                   HelpMessage = "Please provide a local target directory for the GitHub files and folders")]
        [string]$DownloadTargetDirectory
    ) #end param

    Begin
    {
        # Write-WithTime -Output "Downloading and installing" -Log $Log
        Write-Output "Downloading and installing"
        $wc = [System.Net.WebClient]::new()
        $RawGitHubUriPrefix = "https://raw.githubusercontent.com"
    } #end begin
    Process
    {
        foreach ($File in $Files)
        {
            Write-Output "Processing $File..."
            # File download
            $uri = $RawGitHubUriPrefix, $Owner, $Repository, $Branch, $sourceDirectory, $File -Join "/"
            Write-Output "Attempting to download from $uri"
            $DownloadTargetPath = Join-Path -Path $DownloadTargetDirectory -ChildPath $File
            $wc.DownloadFile($uri, $DownloadTargetPath)
        } #end foreach
    } #end process
    End
    {
    } #end end
} #end function

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
[string[]]$localModulesToInstall = @($azurePreferredModule,"AzureAutomation")
# https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-1.1.0
Remove-ARMDeployPSModule -ModuleToRemove $azureNonPreferredModule -Verbose
# Get required PowerShellGallery.com modules.
Get-ARMDeployPSModule -ModulesToInstall $localModulesToInstall -PSRepository $PSModuleRepository -Verbose
#endregion

#region 03.00 Athenticate to Subscription
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
#endregion 03.00

#region 04.00 Select target VM
Do
{
    $vmList = Get-AzVM -ResourceGroupName $rgpName -Verbose
    Write-Output $header.SeparatorDouble
    Write-Output "The list of Azure VMs in resource group $rgpName are:"
    Write-Output $header.SeparatorDouble
    $vmList.Name
    Write-Output $header.SeparatorSingle
    $targetVMName = Read-Host "Enter target Windows 2019 VM node to either configure as or reverted from a PKI server role (Active Directory Certificate Services)"
    Write-Output $header.SeparatorSingle
} # end do
Until ($targetVMName -in $vmlist.name)
#endregion 04.00

#region Step 05.00 Provide VM credentials
$adminUserName = Read-Host "Enter administrator user name for PKI server configuration"
$adminCred = Get-Credential -UserName $adminUserName -Message "Enter password for user: $adminUserName"
# Send automation credential for DSC configuration to automation account
New-AzAutomationCredential -ResourceGroupName $rgpName -AutomationAccountName $aaaName -Name $domainAdminCred -Value $adminCred -Verbose
#endregion 05.00

# Cleanup *.ps1 and *.psd1 artifacts from previous execution
Write-Output "Cleaning up DSC artifacts from previous script exectuion."
Get-ChildItem -Path $LogDirectory -File | Where-Object {$_.Extension -ne '.log'} | Remove-Item -Force -ErrorAction SilentlyContinue -Verbose

#region 06.00 Retrieve artifacts
Get-GitHubRepositoryFile -Owner $repoOwner -Repository $repoName -Branch $repoBranch -Directory $sourceDirectory -Files $filesToDownload -DownloadTargetDirectory $LogDirectory -Verbose
#endregion 06.00

#region 07.00 Import configuration
$localConfigurationFilePath = Join-Path $LogDirectory -ChildPath $configurationFile
Import-AzAutomationDscConfiguration -AutomationAccountName $aaaName -ResourceGroupName $rgpName -SourcePath $localConfigurationFilePath -Published -Confirm:$false -LogVerbose $true -Verbose -Force
#endregion 07.00

#region 08.00 Import DSC Resource modules into Automation account if it has not already been imported.
foreach ($automationModule in $modulesForAzureAutomation)
{
    $moduleName = (Get-AzAutomationModule -AutomationAccountName $aaaName -Name $automationModule -ResourceGroupName $rgpName -ErrorAction SilentlyContinue).Name
    # Install module if it doesn't already exist
    if (-not($moduleName -eq $automationModule))
    {
        New-AutomationAccountModules -ResourceGroupName $rgpName -Modules $automationModule -AutomationAccountName $aaaName -Verbose
        # Wait for 100 seconds to ensure each module has sufficient time to import to the modules asset of the automation account
        Start-Sleep -Seconds 100
    } # end if
} # end foreach
#endregion 08.00

#region 09.00 Compile configuration
# https://docs.microsoft.com/en-us/azure/automation/automation-dsc-compile#compile-a-dsc-configuration-in-azure-state-configuration
$configName = $configurationFile.Split(".")[0]

$pkiConfigDataPath = Join-Path -Path $LogDirectory -ChildPath $configDataFile

# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-powershelldatafile?view=powershell-7
$pkiConfigData = Import-PowerShellDataFile  -Path $pkiConfigDataPath
$CompilationJob = Start-AzAutomationDscCompilationJob -ResourceGroupName $rgpName -AutomationAccountName $aaaName -ConfigurationName $configName -ConfigurationData $pkiConfigData -Verbose
while($null -eq $CompilationJob.EndTime -and $null -eq $CompilationJob.Exception)
{
    $CompilationJob = $CompilationJob | Get-AzAutomationDscCompilationJob
    Start-Sleep -Seconds 3
} # end while

$CompilationJob | Get-AzAutomationDscCompilationJobOutput –Stream Any
#endregion 09.00

#region 10.00 Register node
# https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/dsc-overview
$nodeConfigurationName = ($CompilationJob).ConfigurationName + ".localhost"

$nodeRegistration = $null

Write-Output "Checking for node registration of VM: $targetVMName"
$nodeRegistration = Get-AzAutomationDscNode -ResourceGroupName $rgpName -AutomationAccountName $aaaName -Name $targetVMName

if (-not($nodeRegistration) -or ($nodeRegistration.Status -eq 'failed'))
{
    Write-Output "VM: $targetVMName has not yet been registered as a node. Registering now..."
    Register-AzAutomationDscNode -ResourceGroupName $rgpName `
    -AutomationAccountName $aaaName `
    -ConfigurationMode ApplyAndAutocorrect `
    -RebootNodeIfNeeded:$true `
    -AllowModuleOverwrite:$true `
    -ActionAfterReboot ContinueConfiguration `
    -ConfigurationModeFrequencyMins 15 `
    -RefreshFrequencyMins 30 `
    -NodeConfigurationName $nodeConfigurationName `
    -AzureVMResourceGroup $rgpName `
    -AzureVMName $targetVMName `
    -Verbose
} # end if
elseif ($nodeRegistration.Name -eq $targetVMName)
{
    Write-Output "VM: $targetVMName has already been registered as a node. Skipping node registrtaion."
} # end else
#endregion 10.00

#region 11.00 Get status
# https://docs.microsoft.com/en-us/azure/automation/troubleshoot/desired-state-configuration
# https://github.com/Azure/azure-powershell/issues/10404
$dscNode = Get-AzAutomationDscNode -ResourceGroupName $rgpName -AutomationAccountName $aaaName -Name $targetVMName
do
{
    Write-Output $SeparatorSingle
    Write-Output "Getting DSC configuration status..."
    $getDscConfigStatus = Get-AzAutomationDscNodeReport -ResourceGroupName $rgpName -AutomationAccountName $aaaName -NodeId $dscNode.Id -Latest -Verbose
    $getDscConfigStatus
    Start-Sleep -Seconds 5 -Verbose
} Until ($getDscConfigStatus.Status -eq 'Compliant')
#endregion 11.00

# Restart VM to apply the configuration.
Restart-AzVM -ResourceGroupName $rgpName -Name $targetVMName -Verbose

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

#region 11.00 Verify configuration
Write-Output $SeparatorSingle
Write-Output "To verify that the Certificate Server is installed log into the target server via RDP or Azure Bastion, then open a powershell console and type: certsrv.msc and press enter."
Write-Output "The Certificate Authority MMC console should appear."
#region 11.00

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
#endregion 02.00