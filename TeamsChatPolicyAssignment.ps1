<#
NOTE: This script is easily adaptable to assigning various Teams policies.

Teams Chat Policy
This script uses an AD Group to control chat permissions in Teams.
This script logs into Office 365 Powershell and assigns a specified chat policy to everyone in the <TeamsChatRestriction> ADGroup
Users in the above AD Group are added to or removed from the specified chat policy


PREREQUISITES
.Net 4.8
Powershell modules
MicrosoftTeams
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Find-Module MicrosoftTeams | Install-Module
	Import-module MicrosoftTeams
SkypeOnlineConnector
	https://www.microsoft.com/en-us/download/details.aspx?id=39366#:~:text=Skype%20for%20Business%20Online,%20Windows,the%20use%20of%20Windows%20PowerShell.



Updates to make work in your environment:
Line 45 - C:\AutomationService.txt - Set to your hashed password file
Line 46 - "AutomationServiceAccount@contoso.com" Set to your service account
Line 60 - <TeamsChatRestrictionADGroup>  Set to your AD group name
Line 70 - <Restricted Chat Policy>  Set to your policy name
Line 78 - <Restricted Chat Policy>  Set to your policy name
Line 104 - <servername>  Update with the server name that the script is run from (not necessary)
Line 108 - Update Email addresses, SMTP server, Server name


Author: Erik Crider
Date: 06/11/2020
#>

##           Various settings to ensure that the script can run. Allows Basic Auth, Updates the powershell Execution Policy
$regpath = "HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client"
$name = "AllowBasic"
$val = "1"
SET-ITEMPROPERTY -PATH $regpath -NAME $name -VALUE $val
Set-ExecutionPolicy unrestricted

##           Get credentials and pass them into a variable
##           The file for the password MUST be made on the same server that this is run from
$password = get-content C:\AutomationService.txt | convertto-securestring
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist "AutomationServiceAccount@contoso.com",$password
$UserCredential = $credentials

##           Login to Skype Online
$sessionOption = New-PSSessionOption -SkipRevocationCheck 
$skypeSession = New-CsOnlineSession -OverridePowerShellUri "https://admin0a.online.lync.com/OcsPowerShellOAuth" -Credential $UserCredential
Import-PSSession $skypeSession -ErrorAction SilentlyContinue


##           Login to Microsoft Teams
$TeamsSession = Connect-MicrosoftTeams -Credential $UserCredential

##           Variable to hold all users of the <TeamsChatRestriction> ADGroup
$SAName =@()
$SAName = get-adgroupmember <TeamsChatRestrictionADGroup>  | select -expandproperty samaccountname

##           Grab "emailaddress" attribute from the AD account of everyone in the <TeamsChatRestriction> ADGroup and assign to variable
$UserIDs = @()
Foreach ($S in $SAName)
{
$UserIDs += get-aduser $S -properties emailaddress | select -expandproperty emailaddress
}

##	Differencing the users to add and remove compared to whats already enabled
$RestrictedMessagingUsers = Get-CsOnlineUser -ResultSize unlimited | where {$_.TeamsMessagingPolicy -eq "<Restricted Chat Policy>"}
$RemoveRestriction = $RestrictedMessagingUsers.UserPrincipalName | where {$_ -notin $UserIDs}
$AddRestriction = $UserIDs | where {$_ -notin $RestrictedMessagingUsers.UserPrincipalName}


##	Add users to Restrction
If ($AddRestriction.count -gt 0) {
Foreach ($a in $AddRestriction){
Grant-CsTeamsMessagingPolicy $a -PolicyName "<Restricted Chat Policy>"}
} else {write-output "No Users in Add Group"}

##	Remove users no longer in <TeamsChatRestriction> ADGroup from chat restriction
If ($RemoveRestriction.count -gt 0) {
Foreach ($r in $RemoveRestriction){
Grant-CsTeamsMessagingPolicy $r -PolicyName $null}
} else {write-output "No Users in Add Group"}


##	Variables to force users as list in email
[string]$Removed
foreach ($Ruser in $RemoveRestriction) {$Removed = $Removed + $Ruser + "`r`n"}
[string]$Added
foreach ($Auser in $AddRestriction) {$Added = $Added + $Auser + "`r`n"}

##	Email body
$body =
@"
Users added to Chat Restriction:`r
$Added `r
`r
`r
Users removed from Chat Restriction:`r
$Removed `r
`r
Teams Chat Restriction Job has run. Job runs on server <servername>`r
"@
$body

Send-MailMessage -To <emailaddress> -From AutomationReport@<contoso>.com -Subject "TeamsChat Restriction Job Completed" -SmtpServer <SMTPserver.domain.com> -Body $Body




##	NOTES
##	To verify manually what messaging policy that is on an account log into SkypeOnlinePowershell and run the below command
##		Get-CsOnlineUser "test1@contoso.com" | fl TeamsMessagingPolicy
