
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
      Azure resource group, and optionally updates them.
   .DESCRIPTION
      The script first uses the "az" command-line interface to download a list
      of all current Arc extensions.  This list is parsed and used by cmdlets
      from the Az.ConnectedMachine module to list, and optionally upgrade, all
      extensions with updates for all Azure Arc systems in a given Resource Group.

      Pre-Requisites:
      1) Install-Module Az.ConnectedMachine
      2) Install the Az cli package.  This can be downloaded from
         https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli
         or it can be installed via WinGet: winget install -e --id Microsoft.AzureCLI
      3) Update the $resourceGroup variable below to the name of the Resource
         Group containing the systems you'd like to assess.  The script assumes
         you're already logged in to Azure and have set the subscription to be
         managed when you logged in.
   .NOTES
      Name: Manage-ArcExtensions.ps1
      Author: Scott Brondel, sbrondel@microsoft.com
      Version 1.0 / July 2, 2025
       - Initial Release
   .EXAMPLE
      PS C:\> Manage-ArcExtensions.ps1
      PS C:\> Manage-ArcExtensions.ps1 -CheckOnly
      PS C:\> Manage-ArcExtensions.ps1 -Update
   .OUTPUTS
      A .csv file created in the same folder as this script, named for
      the contents of the $OutputFile variable.
   .LINK
      https://github.com/sbrondel/scripts/Manage-AzureArcExtensions
#>


# Pre-requisites:
# 1) install-module Az.ConnectedMachine
# 2) Register an AAD Application, and fill in your Tenant, ApplicationID, 
#    and ClientSecret variables below.  Example at
#    https://learn.microsoft.com/en-us/graph/tutorials/powershell?tabs=aad&tutorial-step=1
# 3) Highly encourged to use PowerShell 7.x or higher, and not built-in Windows PowerShell
#    for massive speed improvements




[CmdletBinding(DefaultParameterSetName = 'CheckOnly')]
param (
    [Parameter(ParameterSetName = 'CheckOnly')]
    [switch]$CheckOnly = $true,

    [Parameter(ParameterSetName = 'Update')]
    [switch]$Update
)

############# Modify these lines for your environment as appropriate #############
$resourceGroup = 'ArcRG'


function Update-Extension {
    param (
        $resourceGroup,
        $machine,
        $extension,
        $oldVersion,
        $newVersion
    )
    $target = @{$extension = @{"targetVersion" = $version } }
    write-host "Starting job to update" $extension "on" $machine "from" $oldVersion "to" $newVersion
    Update-AzConnectedExtension -ResourceGroupName $resourcegroup -MachineName $machine -ExtensionTarget $target -AsJob | Out-Null
    Start-Sleep -Seconds 5  # added delay to help ensure many out-of-date extensions can patch in a single run
}

<# 
PS C:\> $extensions = get-azconnectedmachineextension -ResourceGroupName ArcRG -MachineName ET ; foreach ($extension in $extensions) {$extName = $extension.publisher+"."+$extension.Name; $extPair = $extName+","+$extension.TypeHandlerVersion; write-host $extPair}
Microsoft.Azure.Security.Monitoring.AzureSecurityWindowsAgent,1.8.0.76
Qualys.WindowsAgent.AzureSecurityCenter,1.0.0.20
Microsoft.CPlat.Core.WindowsPatchExtension,1.5.68
Microsoft.Azure.Monitor.AzureMonitorWindowsAgent,1.26.0.0
Microsoft.Azure.AzureDefenderForServers.MDE.Windows,1.0.9.5
Microsoft.SoftwareUpdateManagement.WindowsOsUpdateExtension,1.0.20.0 #>

function Update-LookupTable {
    Write-Host "Getting list of latest extensions, this will take a minute or two..."
    $currentVersions = az vm extension image list --latest
    $currentVersions = $currentVersions | ConvertFrom-Json
    foreach ($extension in $currentVersions) {
        $fullName = $extension.Publisher + "." + $extension.Name;
        $lookupTable[$fullName] = $extension.version
    }

    $lookupTable | ft -autosize | out-file -filepath .\lookupTable.txt
}

function Get-ArcMachineExtensions {
    param (
        $resourceGroup,
        $machine
    )
    Write-Host "Getting extensions for $machine in Resource Group $resourceGroup"

    # Get all extensions for this system not in the Creating or Updating state.  This means we will try to
    # update extensions that are currently in the Failed state.
    $extensions = get-azconnectedmachineextension -ResourceGroupName $resourceGroup -MachineName $machine | Where-Object { $_.ProvisioningState -notin "Creating", "Updating" }
    foreach ($extension in $extensions) {
        # using InstanceViewType to get the correct name, as "Name" can sometimes differ from the Type in the portal.
        # Example:  Name of MicrosoftDefenderForSQL but Type/InstanceViewType is AdvancedThreatProtection.Windows
        $extName = $extension.publisher + "." + $extension.InstanceViewType

        if ($extension.TypeHandlerVersion -ne $lookupTable.$extName) {
             if ($PSCmdlet.ParameterSetName -eq 'Update') {
                
                Update-Extension -resourcegroup $resourceGroup -machine $machine -extension $extName -oldVersion $extension.TypeHandlerVersion -newVersion $lookupTable.$extName
            }
            else {
                Write-Host $machine "needs to update" $extname "from" $extension.TypeHandlerVersion "to" $lookupTable.$extName
            }
        }
        else {
        }
    }
   
    Write-Host ""
}


function Get-ActiveJobs {
    return (get-job | where {($_.State -eq "Running") -and ($_.Name -eq "Update-AzConnectedExtension_UpgradeExpanded")}).count
}

################# Main Script Start ##########################

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "No parameters were specified, operating in -CheckOnly reporting mode."
    Write-Host "Use the -Update parameter to update Azure Arc extensions."
    Write-Host ""
}
elseif ($PSCmdlet.ParameterSetName -eq 'CheckOnly') {
    Write-Host "Running in -CheckOnly reporting mode..."
    Write-Host ""
}
elseif ($PSCmdlet.ParameterSetName -eq 'Update') {
    Write-Host "Running in -Update mode."
    Write-Host "All out-of-date extensions will be updated, including those with Auto-Update enabled."
    Write-Host ""
}
else {
    Write-Host "Unknown parameter entered, exiting..."
    exit
}

# Create our lookup table for extension and version
$lookupTable = @{}

# Populate the table
Update-LookupTable

# Get Azure Arc machines in resource group
$machines = Get-AzConnectedMachine -ResourceGroupName $resourceGroup  | where { $_.ProvisioningState -eq "Succeeded" -and $_.Status -eq "Connected" }
$machineCount = $machines.count

# Begin main loop, with progress bar
Write-Host "Discovered" $machineCount "Azure Arc systems in Resource Group $resourceGroup"
Write-Host ""
$currentMachine = 1

foreach ($machine in $machines) {
    $machineProgress = ($currentMachine - 1) / $machines.count * 100
    $machineProgress = [math]::Round($machineProgress, 2)
    Write-Progress -Activity "Checking Azure Arc Extensions" -Status "Working on server $currentMachine of $machineCount, $machineProgress% Complete" -PercentComplete $machineProgress -id 1
    Get-ArcMachineExtensions -resourceGroup $resourceGroup -machine $machine.Name
    $currentMachine += 1
    
    # Check if we've reached the last system, and if so remove the progress bar
    if($currentMachine -gt $machines.count) {
        Write-Progress -Activity "Checking Azure Arc Extensions" -id 1 -Completed
    }
}

#start-sleep 5

$activeJobs = Get-ActiveJobs
while ($activeJobs -gt 0) {
    $curTime = (Get-Date -Format "hh:mm:ss tt")
    if($activeJobs -gt 1) {Write-host -NoNewLine "`r$curTime - $activeJobs update jobs are still running.";}
    else {
        Write-Host -NoNewLine "`r$curTime - $activeJobs update job is still running."
    }
    start-sleep 10
    $activeJobs = Get-ActiveJobs
}
Write-Host ""
Write-Host "All update jobs are complete."

