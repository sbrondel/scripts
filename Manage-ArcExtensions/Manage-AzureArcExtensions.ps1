
# DISCLAIMER
# This software (or sample code) is not supported under any Microsoft standard
# support program or service. The software is provided AS IS without warranty
# of any kind. Microsoft further disclaims all implied warranties including,
# without limitation, any implied warranties of merchantability or of fitness
# for a particular purpose. The entire risk arising out of the use or
# performance of the software and documentation remains with you. In no event
# shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of the software be liable for any damages whatsoever
# (including, without limitation, damages for loss of business profits, business
# interruption, loss of business information, or other pecuniary loss) arising
# out of the use of or inability to use the software or documentation, even if
# Microsoft has been advised of the possibility of such damages.

<#
   .SYNOPSIS
      Reports on all out-of-date extensions on Azure Arc systems in a specified
      Azure resource group, and optionally updates them. and if the Update switch is specified, updates them.

   .DESCRIPTION
      The script first uses the "az" command-line interface to download a list of all current Arc extensions.  This list is parsed and used by cmdlets from the Az.ConnectedMachine module to list, and optionally upgrade, all extensions with updates for all Azure Arc systems in a given Resource Group.

    .PARAMETER Update
      The script will attempt to update all out-of-date extensions on all
      Azure Arc systems in the specified Resource Group.

    .PARAMETER ResourceGroup
      The name of the Azure Resource Group containing the Azure Arc systems
      to be assessed.

   .NOTES
        Pre-Requisites:
        1) Install-Module Az.ConnectedMachine
        2) Install the Az cli package.  This can be downloaded from
         https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli
         or it can be installed via WinGet: winget install -e --id Microsoft.AzureCLI
        3) Update the $resourceGroup variable below to the name of the Resource Group containing the systems you'd like to assess.  The script assumes you're already logged in to Azure and have set the subscription to be
        managed when you logged in.


        Pre-requisites:
        1) Register an AAD Application, and fill in your Tenant, ApplicationID, and ClientSecret variables below.  Example at
        https://learn.microsoft.com/en-us/graph/tutorials/powershell?tabs=aad&tutorial-step=1
        2) Highly encouraged to use PowerShell 7.x or higher, and not built-in Windows PowerShell for massive speed improvements

        Name: Manage-ArcExtensions.ps1
        Author: Scott Brondel, sbrondel@microsoft.com
        Version History:
         1.0  07/02/2025 Scott Brondel     - Initial Release
         1.1  11/04/2025 Francois Fournier - Added Resource Group Parameter and more logging and fixed minor bugs
         1.2  11/04/2025 Francois Fournier - Integrated logging function

   .EXAMPLE
      Manage-ArcExtensions.ps1
      Manage-ArcExtensions.ps1 -ResourceGroup <ResourceGroupName>
      Manage-ArcExtensions.ps1 -Update

   .OUTPUTS
      A .csv file created in the same folder as this script, named for the contents of the $OutputFile variable.
      .log file created in the same folder as this script, named for the ScriptName variable.

   .LINK
      https://github.com/sbrondel/scripts/Manage-AzureArcExtensions
#>
<#
#Requires -Version <N>[.<n>]
#Requires -Modules { <Module-Name> | <Hashtable> }
#Requires -PSEdition <PSEdition-Name>
#Requires -RunAsAdministrator
#>
#requires -Modules Az.ConnectedMachine

[CmdletBinding()]
param (

    [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Message' , Mandatory = $false, Position = 0)]
    [string]$ResourceGroup = 'ArcRG',
    [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Message' , Mandatory = $false, Position = 0)]
    [switch]$Update
)

<#
.SYNOPSIS
	Log and display message

.DESCRIPTION
	Display message on the screen  with appropriate level while Creating a log file for permanent storage

.PARAMETER Message
  String parameter for Message

.PARAMETER Level
  Specifies the level of the information message. Valid values are:
	'INFO', 'WARNING', 'ERROR', 'DEBUG'

.INPUTS
	.none

.OUTPUTS
	Log: "$ScriptPath\$ScriptName-$LogDate.log"

.Example
		Write-Log -Message 'This is an informational message.' -Level 'INFO'
		Write-Log -Message 'This is a warning message.' -Level 'WARNING'
		Write-Log -Message 'This is an error message.' -Level 'ERROR'
		Write-Log -Message 'This is a debug message.' -Level 'DEBUG'

.Notes
    Author: Francois Fournier
    Created: 2025-01-01
    Version: 1.0.0
    Last Updated: 2025-01-01
    License: MIT License

    V1.0 Initial version

.DISCLAIMER
  This script is provided "as is" without warranty of any kind, either express or implied.
  Use of this script is at your own risk. The author assumes no responsibility for any
  damage or loss resulting from the use or misuse of this script.

  You are free to modify and distribute this script, provided that this disclaimer remains
  intact and visible in all copies and derivatives.

  Always test scripts in a safe environment before deploying to production.

.link

 #>
<#
#Requires -Version <N>[.<n>]
#Requires -Modules { <Module-Name> | <Hashtable> }
#Requires -PSEdition <PSEdition-Name>
#Requires -Modules PSLogging
#>


#=============================================================================
# region Functions
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$level] $message"
    Add-Content -Path $logFile -Value $logEntry
    switch ($Level) {
        'INFO' {
            Write-Host "[INFO] $Message" -ForegroundColor Green
        }
        'WARNING' {
            Write-Host "[WARNING] $Message" -ForegroundColor Yellow
        }
        'ERROR' {
            Write-Host "[ERROR] $Message" -ForegroundColor Red
        }
        'DEBUG' {
            Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
        }
    }
}

#endregion Functions

function Update-Extension {
    param (
        $resourceGroup,
        $machine,
        $extension,
        $oldVersion,
        $newVersion
    )
    $target = @{$extension = @{'targetVersion' = $version } }
    Write-log "Starting job to update $extension on $machine from $oldVersion to $newVersion" -Level INFO
    Update-AzConnectedExtension -ResourceGroupName $ResourceGroup -MachineName $machine -ExtensionTarget $target -AsJob | Out-Null
    Start-Sleep -Seconds 5  # added delay to help ensure many out-of-date extensions can patch in a single run
}

function Update-LookupTable {
    Write-log 'Getting list of latest extensions, this will take a minute or two.' -Level INFO
    $currentVersions = az vm extension image list --latest
    $currentVersions = $currentVersions | ConvertFrom-Json
    foreach ($extension in $currentVersions) {
        $fullName = $extension.Publisher + '.' + $extension.Name;
        $lookupTable[$fullName] = $extension.version
    }

    #$lookupTable | Sort-Object name | Format-Table -AutoSize | Out-File -FilePath .\lookupTable.txt
    $lookupTable.GetEnumerator() | Sort-Object Name | Format-Table -AutoSize | Out-File -FilePath .\lookupTable.txt
}

function Get-ArcMachineExtensions {
    param (
        $resourceGroup,
        $machine
    )
    Write-log "Getting extensions for $machine in Resource Group $resourceGroup" -Level INFO

    # Get all extensions for this system not in the Creating or Updating state.  This means we will try to
    # update extensions that are currently in the Failed state.
    $extensions = Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroup -MachineName $machine | Where-Object { $_.ProvisioningState -notin 'Creating', 'Updating' }
    foreach ($extension in $extensions) {
        # using InstanceViewType to get the correct name, as "Name" can sometimes differ from the Type in the portal.
        # Example:  Name of MicrosoftDefenderForSQL but Type/InstanceViewType is AdvancedThreatProtection.Windows
        $extname = $extension.publisher + '.' + $extension.name

        if ($extension.TypeHandlerVersion -ne $lookupTable.$extName) {
            if ($Update) {
                Write-Log 'Updating the extension.' -Level WARNING
                Update-Extension -resourcegroup $ResourceGroup -machine $machine -extension $extName -oldVersion $extension.TypeHandlerVersion -newVersion $lookupTable.$extName
            } else {
                Write-log "$machine needs to update $extname from $($extension.TypeHandlerVersion) to $($lookupTable.$extName)" -Level Info
            }
        } else {
            Write-log "$machine $extName is up to date." -Level INFO
        }
    }

    Write-log "`n" -Level INFO
}

function Get-ActiveJobs {
    return (Get-Job | Where-Object { ($_.State -eq 'Running') -and ($_.Name -eq 'Update-AzConnectedExtension_UpgradeExpanded') }).count
}

################# Main Script Start ##########################

#=============================================================================
# region Variables
$LogDate = Get-Date -Format yyyyMMdd-HHmmss
$ScriptPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$ScriptName = Split-Path -Path $MyInvocation.MyCommand.Definition -Leaf
$logPath = "$ScriptPath"
$LogName = ($ScriptName).Replace('.ps1', '') + '-' + $LogDate + '.log'
$LogFile = $logPath + '\' + "$LogName"

#endregion Variables
Write-log 'Starting job to check / update Azure / Arc extensions.' -Level INFO
Write-log "`n" -Level INFO

if ($update) {
    Write-log 'Running in -Update mode.' -Level Warning
    Write-log 'All out-of-date extensions will be updated, including those with Auto-Update enabled.' -Level Warning
    Write-log "`n" -Level Warning

} else {
    Write-log 'Running in -CheckOnly reporting mode.' -Level INFO
    Write-log 'Use the -Update parameter to update Azure Arc extensions.' -Level Warning
    Write-log "`n" -Level INFO
}


# Create our lookup table for extension and version
$lookupTable = @{}

# Populate the table
Update-LookupTable

# Get Azure Arc machines in resource group
$machines = Get-AzConnectedMachine -ResourceGroupName $resourceGroup | Where-Object { $_.ProvisioningState -eq 'Succeeded' -and $_.Status -eq 'Connected' }
$machineCount = $machines.count

# Begin main loop, with progress bar
Write-log "Discovered $machineCount Azure Arc systems in Resource Group $resourceGroup" -Level INFO
Write-log "`n" -Level INFO
$currentMachine = 1

foreach ($machine in $machines) {
    $machineProgress = ($currentMachine - 1) / $machines.count * 100
    $machineProgress = [math]::Round($machineProgress, 2)
    Write-Progress -Activity 'Checking Azure Arc Extensions' -Status "Working on server $currentMachine of $machineCount, $machineProgress% Complete" -PercentComplete $machineProgress -Id 1
    Get-ArcMachineExtensions -resourceGroup $resourceGroup -machine $machine.Name
    $currentMachine += 1

    # Check if we've reached the last system, and if so remove the progress bar
    if ($currentMachine -gt $machines.count) {
        Write-Progress -Activity 'Checking Azure Arc Extensions' -Id 1 -Completed
    }
}

#start-sleep 5

$activeJobs = Get-ActiveJobs
while ($activeJobs -gt 0) {
    $curTime = (Get-Date -Format 'hh:mm:ss tt')
    if ($activeJobs -gt 1) {
        Write-log "$activeJobs update jobs are still running." -Level INFO
    } else {
        Write-log "$activeJobs update job is still running." -Level INFO
    }
    Start-Sleep 10
    $activeJobs = Get-ActiveJobs
}
Write-log '-----------------------------' -Level INFO
Write-log 'All update jobs are complete.' -Level INFO
Write-log 'Ending job' -Level INFO


