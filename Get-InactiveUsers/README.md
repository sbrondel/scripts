# Get-InactiveUsers
This script searches Azure Active Directory and the Active Directory domain of the currently logged-on user for accounts that have not authenticated in a specified period, matches them on UserPrincipalName, and outputs the LastLogonDate of both AD-only / AAD-sync'd / AAD-only accounts into a .csv file.

An Application will need to be registered in your Azure AD tenant, and TenantID / ApplicationID / ClientSecret stored in variables inside the script.  The Application will also need Graph API Application-style delegations of Auditlog.Read.All and Directory.Read.All .

Azure AD accounts are filtered on UserType = Member.

Pre-Requisites:
1) Install-Module Microsoft.Graph
2) Register an AAD Application, and fill in your Tenant, ApplicationID, and ClientSecret variables.  An example of setting up an AAD Application is at https://learn.microsoft.com/en-us/graph/tutorials/powershell?tabs=aad&tutorial-step=1
3) You are highly encourged to use PowerShell 7.x or higher, and not the built-in Windows PowerShell, for massive speed improvements.  Testing against an environment with over 5,000 inactive accounts showed a 5x speed increase (63 seconds in PowerShell 7.3.0 vs 299 seconds with Windows PowerShell 5.1).

Here's what it looks like in action!
<video width="720" height="480" controls>
  <source src="https://cdn.githubraw.com/sbrondel/scripts/main/media/Get-InactiveUsers.mp4" type="video/mp4">
</video>