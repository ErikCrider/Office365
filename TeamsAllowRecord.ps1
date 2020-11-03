<#
NOTE: This script is easily adaptable to assigning various Teams policies.

Teams Recording Permissions
This script uses an AD Group to control recording permissions in Teams. 
This script logs into Office 365 Powershell and assigns a recording policy to everyone in the <ADGroup> ADGroup

PREREQUISITES ON SERVER
.Net 4.8
Powershell modules
MicrosoftTeams
	## May be needed to access powershell gallery. If used, only active for that PS window ## [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Find-Module MicrosoftTeams | Install-Module
	Import-module MicrosoftTeams
SkypeOnlineConnector
	https://www.microsoft.com/en-us/download/details.aspx?id=39366#:~:text=Skype%20for%20Business%20Online,%20Windows,the%20use%20of%20Windows%20PowerShell.

Updates to make work in your environment:
Line 39 - Hashed password file location for service account
Line 40 - Service account name. e.g. AutomationServiceAccount@contoso.com
Line 55 - Update <ADGroupName> to the desired AD Group Name
Line 84 - Update Email addresses, SMTP server, Server name



Author: Erik Crider
Date: 09/01/2020
#>

##           Various settings to ensure that the script can run. Allows Basic Auth, Updates the powershell Execution Policy
$regpath = "HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client"
$name = "AllowBasic"
$val = "1"
SET-ITEMPROPERTY -PATH $regpath -NAME $name -VALUE $val
Set-ExecutionPolicy unrestricted

##           Get credentials and pass them into a variable
##           The file for the password MUST be made on the same server that this is run from
$password = get-content <automationservicePasswordhashfilelocation>.txt | convertto-securestring
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist "<AutomationServiceAccount>",$password
$UserCredential = $credentials

##           Login to Skype Online
$sessionOption = New-PSSessionOption -SkipRevocationCheck 
$skypeSession = New-CsOnlineSession -OverridePowerShellUri "https://admin0a.online.lync.com/OcsPowerShellOAuth" -Credential $UserCredential
Import-PSSession $skypeSession -ErrorAction SilentlyContinue


##           Login to Microsoft Teams
$TeamsSession = Connect-MicrosoftTeams -Credential $UserCredential


##           Variable to hold all users of the AD Group <ADGroupName>
$SAName =@()
$SAName = get-adgroupmember <ADGroupName> | select -expandproperty samaccountname

##           Grab "emailaddress" attribute from the AD account of everyone in the <ADGroupName> group and assign to variable
$UserIDs = @()
Foreach ($S in $SAName)
{
$UserIDs += get-aduser $S -properties emailaddress | select -expandproperty emailaddress
}


##	Differencing the users to add and remove compared to whats already enabled
$TeamsMeetingUsers = Get-CsOnlineUser -ResultSize unlimited | where {$_.TeamsMeetingPolicy -eq "AllowRecord"}
$RemoveRecord = $TeamsmeetingUsers.UserPrincipalName | where {$_ -notin $UserIDs}
$AddRecord = $UserIDs | where {$_ -notin $TeamsmeetingUsers.UserPrincipalName}

##	Add users to AllowRecord policy
If ($AddRecord.count -gt 0) {
Foreach ($a in $AddRecord){
Grant-CsTeamsMeetingPolicy  $a -PolicyName "AllowRecord"}
} else {write-output "No Users in Add Group"}

##	Remove users no longer in SG-365-Stream-ContentCreators
If ($RemoveRecord.count -gt 0) {
Foreach ($r in $RemoveRecord){
Grant-CsTeamsMeetingPolicy  $r -PolicyName $null}
} else {write-output "No Users in Add Group"}


##	Send Message notifying that the job ran
Send-MailMessage -To <emailaddress> -From AutomationReport@<contoso>.com -Subject "Teams AllowRecord Job Completed" -SmtpServer <SMTPserver.domain.com> -Body "AllowRecord Job has run. Job runs on server <server>"


##	NOTES
##	To verify manually what messaging policy that is on an account log into SkypeOnlinePowershell and run the below command
##		Get-CsOnlineUser "tellertest1@contoso.com" | ft TeamsMeetingPolicy


