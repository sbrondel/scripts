# Manage-ArcExtensions
This script will iterate through all Azure Arc systems in a given Resource Group, and either report-on or upgrade any installed extensions where an update is available.  This works whether or not the extension supports auto-upgrade.

The script needs the Az command-line-interface installed, as well as the Az.ConnectedMachine module.  It assumes that you've already logged in to both Az and Connect-AzAccount and have set the target subscription appropriately.

Azure AD accounts are filtered on UserType = Member.

Pre-Requisites:
1) Install-Module Az.ConnectedMachine
2) Install the Az cli package.  This can be downloaded from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli or it can be installed via WinGet: winget install -e --id Microsoft.AzureCLI
3) Update the $resourceGroup variable below to the name of the Resource Group containing the systems you'd like to assess.  The script assumes you're already logged in to Azure and have set the subscription to be managed when you logged in.

