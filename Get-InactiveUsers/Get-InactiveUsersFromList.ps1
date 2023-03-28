
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
      Creates a report of inactive Azure AD and AD accounts from a user-defined
      input list.
   .DESCRIPTION
      Searches Azure Active Directory and the Active Directory domain of the
      currently logged-on user for a user-provided list of accounts, identifies
      those which have not authenticated in a specified period, matches them on
      UserPrincipalName, and outputs the LastLogonDate of both AAD-sync'd
      accounts into a .csv file.

      To minimize the amount of GraphAPI calls and not run into the potential
      of throttling due to making one GraphAPI call for each UserPrincipalName
      provided, this script follows the behavior of Get-InactiveUsers and
      will dump all AAD accounts meeting the specified $InactiveDays threshold.
      The script will then only report on accounts inside the provided UserList
      with a matching UPN in Active Directory and Azure Active Directory.

      An Application will need to be registered in your Azure AD tenant, and
      TenantID / ApplicationID / ClientSecret provided in the variables
      below.  The Application will also need Graph API Application-style
      delegations of Auditlog.Read.All and Directory.Read.All .

      Azure AD accounts are filtered on UserType = Member.

      Pre-Requisites:
      1) Install-Module Microsoft.Graph
      2) Register an AAD Application, and fill in your Tenant, ApplicationID, 
         and ClientSecret variables below.  Example at
         https://learn.microsoft.com/en-us/graph/tutorials/powershell?tabs=aad&tutorial-step=1
      3) You are highly encourged to use PowerShell 7.x or higher, and not the built-in 
         Windows PowerShell, for massive speed improvements.
      4) Create a text file of UserPrincipalNames to check, one per line.
   .NOTES
      Name: Get-InactiveUsersFromList.ps1
      Author: Scott Brondel, sbrondel@microsoft.com
      Version 1.0 / March 28, 2003
       - Initial Release
   .EXAMPLE
      PS C:\> Get-InactiveUsersFromList.ps1 -UserList users.txt
   .OUTPUTS
      A .csv file created in the same folder as this script, named for
      the contents of the $OutputFile variable.
   .LINK
      https://github.com/sbrondel/scripts/Get-InactiveUsers
#>


# Pre-requisites:
# 1) install-module Microsoft.Graph
# 2) Register an AAD Application, and fill in your Tenant, ApplicationID, 
#    and ClientSecret variables below.  Example at
#    https://learn.microsoft.com/en-us/graph/tutorials/powershell?tabs=aad&tutorial-step=1
# 3) Highly encourged to use PowerShell 7.x or higher, and not built-in Windows PowerShell
#    for massive speed improvements

param(
   [Parameter(Mandatory=$true,
              ParameterSetName="UserList",
              HelpMessage="Name of text file with list of UserPrincipalNames, one per line.")] 
   [string]$UserList
)


# App needs Application delegation for AuditLog.Read.All and Directory.Read.All permissions
$TenantID      = "fill_in_-your-own_-info-rmationhere!"
$ApplicationID = "fill_in_-your-own_-info-rmationhere!"
$ClientSecret  = "fill_in_-your-own_-info-rmationhere!"

# How many days of inactivity should we look for.  Set this to 0 if you'd like an activity
# report for all users provided in UserList regardless of their last logon date.
$InactiveDays = 60

# Name of Output file
$OutputFile = "Inactive AD and AAD Users.csv"

# Convert $InactiveDays into appropriate timespans for AD and AAD
$When = ((Get-Date).AddDays(-$InactiveDays)).Date
$GraphWhen = $When.ToString("yyyy-MM-ddTHH:mm:ssZ")

# Create HTTP message body for Microsoft Graph authentication
$Body = @{    
   Grant_Type    = "client_credentials"
   Scope         = "https://graph.microsoft.com/.default"
   client_Id     = $ApplicationID
   Client_Secret = $ClientSecret
} 

$AADReport = [System.Collections.Generic.List[Object]]::new() 
$FinalReport = [System.Collections.Generic.List[Object]]::new() 

# The following function is used multiple times to process the downloaded AAD
# account information and store the information in the custom $AADReport
# collection
function Process-AADUser() {
   [cmdletbinding()]

   param
   (
      $User
   )

   # Explicitly filtering on Members, exclude apps/guests/etc.
   If ($User.userType -eq 'Member') {  
      #Write-host "User:" $User.userPrincipalName $User.SignInActivity.LastSignInDateTime

      If ($Null -ne $User.SignInActivity) {  # The AAD account has logged in before
         $LastSignIn = Get-Date($User.signInActivity.lastSignInDateTime) -format g
         $DaysSinceSignIn = (New-TimeSpan $LastSignIn).Days
      }
      Else {
         # No sign in data for this user account
         $LastSignIn = "Never / No AAD Sign-in Data" 
         $DaysSinceSignIn = "N/A" 
      }
     
      $ReportLine = [PSCustomObject] @{          
         UPN                 = $User.UserPrincipalName
         DisplayName         = $User.DisplayName
         Email               = $User.Mail
         AAD_ObjectId        = $User.Id
         AD_LastSignIn       = ""
         AD_DaysSinceSignIn  = ""  
         AAD_LastSignIn      = $LastSignIn
         AAD_DaysSinceSignIn = $DaysSinceSignIn
         AAD_UserType        = $User.UserType
      }
      $AADReport.Add($ReportLine) 
   }
}

# Connect to Microsoft Graph and retrieve an access token
$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token" -Method POST -Body $Body
$token = $ConnectGraph.access_token

# Read our list of users to check
try
{
   $Users = Get-Content $UserList
   Write-Host $UserList "contains" $Users.Count "accounts to check."
}
catch {
   Write-host "Error reading from '$UserList'"
}

# Get inactive AD Users from the currently logged-in account's domain
Write-Host "Step 1/5: Checking user list for inactive Active Directory accounts..."

# Create an empty ArrayList for AD users
$ADUsers = New-Object System.Collections.ArrayList

# Check Active Directory for the existence of each provided userPrincipalName
ForEach($User in $Users)
{
   $TempUser = Get-ADUser -Filter { userPrincipalName -eq $User } -Properties samAccountName, userPrincipalName, mail, displayName, LastLogonDate | select-object samAccountName, userPrincipalName, mail, displayName, LastLogonDate
   If($TempUser) {
      $ADUsers.Add($TempUser) | Out-Null
   }
}

Write-Host $ADUsers.Count "inactive Active Directory accounts found from the provided list."
Write-Host ""

# Get inactive AAD users
# Use the following GraphURL line to only return accounts greater than $InactiveDays of activity
$GraphURL = "https://graph.microsoft.com/beta/users?`$select=displayName,userPrincipalName,mail,id,CreatedDateTime,signInActivity,UserType&`$filter=signInActivity/lastSignInDateTime le $GraphWhen &`$top=999"

# The below line can be used instead if you'd like to report on all AAD accounts
#$GraphURL = "https://graph.microsoft.com/beta/users?`$select=displayName,userPrincipalName,mail,id,CreatedDateTime,signInActivity,UserType&`$top=999"

Write-Host "Step 2/5: Checking user list for inactive Azure Active Directory accounts..."
$AADUsers = ""
$AADUsers = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"; ConsistencyLevel = "eventual" } -Uri $GraphURL -Method Get

# Process our first 999 downloaded AAD accounts
ForEach ($AADUser in $AADUsers.Value) {  
   ForEach($ADUser in $ADUsers) {
      if($ADUser.userPrincipalName -ieq $AADUser.userPrincipalName) {
         Process-AADUser($AADUser)
      }
   }
} 

# We have at most 999 records - are there more, is paging needed?
$PagingLink = $AADUsers.'@Odata.NextLink'

While ($Null -ne $PagingLink) {
   # Grab next page of users
   Write-Host "Still processing..."
   $AADUsers = Invoke-WebRequest -Method GET -Uri $PagingLink -ContentType "application/json" -Headers @{Authorization = "Bearer $($token)"; ConsistencyLevel = "eventual" } 
   $AADUsers = $AADUsers | ConvertFrom-JSon
   ForEach ($AADUser in $AADUsers.Value) {  
      ForEach($ADUser in $ADUsers) {
         if($ADUser.userPrincipalName -ieq $AADUser.userPrincipalName) {
            Process-AADUser($AADUser)
         }
      }
   }
   $PagingLink = $AADUsers.'@Odata.NextLink'
}

Write-Host $AADReport.Value.Count "inactive Azure Active Directory accounts found in the provided list."
Write-Host ""

# Loop through all Azure AD accounts, looking for matching AD accounts (on userPrincipalName)
# for consolidated reporting
Write-Host "Step 3/5: Comparing Azure AD User list to AD..."
$counter = 1
ForEach ($ReportUser in $AADReport) {
   $Match = 0
   ForEach ($ADUser in $ADUsers) {
      if($ADUser.userPrincipalName -eq $ReportUser.UPN) {
         If ($Null -ne $ADUser.LastLogonDate) {
            $LastSignIn = Get-Date($ADUser.LastLogonDate) -format g
            $DaysSinceSignIn = (New-TimeSpan $LastSignIn).Days
         }
         Else {
            # No sign in data for this user account
            $LastSignIn = "Never / No AD Sign-in Data" 
            $DaysSinceSignIn = "N/A" 
         }

         # Fill in the missing AD fields for this AAD user
         $ReportUser.AD_LastSignIn = $LastSignIn
         $ReportUser.AD_DaysSinceSignIn = $DaysSinceSignIn
         $Match = 1
         $FinalReport.Add($ReportUser)
      }
   }
   if(!$Match) { # if no match, then note that no AD data was found
      $ReportUser.AD_LastSignIn = "Never / No AD Sign-in Data" 
      $ReportUser.AD_DaysSinceSignIn = "N/A"
      if($null -ne $ReportUser.UPN) {
         $FinalReport.Add($ReportUser)
      }
   }

   # Write out progress bar
   $progress = ($counter - 1) / $AADReport.Count * 100
   Write-Progress -Activity "Processed AAD User $counter" -Status "$progress% Complete" -PercentComplete $progress
   $counter = $counter + 1
}
Write-Host ""

Write-Host "Step 4/5: Comparing AD User list to Azure AD..."
$counter = 1
ForEach ($ADUser in $ADUsers) {
   $Match = 0
   
   ForEach($ReportUser in $AADReport) {
      if($ReportUser.UPN -eq $ADUser.userPrincipalName) {
         # If we find a match, it's already been reported in the previous sweep.
         # Just flag it, nothing else to do for this account
         $Match = 1 
      }
   }
   if(!$Match) { # No match, so this is an AD account not sync'd to AAD,
                 # or it is sync'd but has a recent LastLogonDate and
                 # was filtered out of the results due to recent sign-in
      If ($Null -ne $ADUser.LastLogonDate) {
         $LastSignIn = Get-Date($ADUser.LastLogonDate) -format g
         $DaysSinceSignIn = (New-TimeSpan $LastSignIn).Days
      }
      Else {
         # No AD sign in data for this user account
         $LastSignIn = "Never / No AD Sign-in Data" 
         $DaysSinceSignIn = "N/A" 
      }

      # Add this AD-only account to our $FinalReport
      $ReportLine = [PSCustomObject] @{          
         UPN                 = $ADUser.UserPrincipalName
         DisplayName         = $ADUser.DisplayName
         Email               = $ADUser.Mail
         AAD_ObjectId        = "N/A"
         AD_LastSignIn       = $LastSignIn
         AD_DaysSinceSignIn  = $DaysSinceSignIn
         AAD_LastSignIn      = "N/A"
         AAD_DaysSinceSignIn = "N/A"
         AAD_UserType        = "N/A"
      }
      if($null -ne $ReportLine.UPN) {
         $FinalReport.Add($ReportLine)
      }
   }

   # Write out progress
   $progress = ($counter - 1) / $ADUsers.Count * 100
   Write-Progress -Activity "Processed AD User $counter" -Status "$progress% Complete" -PercentComplete $progress
   $counter = $counter + 1
}
Write-Host ""
#$AADReport | sort UPN  | ft UPN, DisplayName, AAD_LastSignIn, AD_LastSignin
#$FinalReport  | sort UPN  | ft UPN, DisplayName, AAD_LastSignIn, AD_LastSignin

Write-Host "Step 5/5: Creating .csv file..."
$FinalReport | export-csv .\$OutputFile -Force
Get-ChildItem .\$OutputFile