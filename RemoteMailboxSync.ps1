<#
RemoteMailbox Script
A RemoteMailbox in Exchange is used to let mail be routed to the cloud mailbox, as well as have access to other OnPrem resources such as Public Folders
This RemoteMailbox is not created automatically so a new user whose mailbox is in the cloud will not get mail sent to them
from on premises servers, printers, scanners, etc. 
This script is to sync on premise and O365 mailboxes. It reaches out to O365 for newly created mailboxes, gets the ExchangeGUID.
It will then reach out to the on Prem Exchange servers to create the remote mailbox, and set the ExchangeGUID. 
If the remotemailbox already exists but the ExchangeGUID is wrong, it will replace the guid with the correct one.
Updates to make work in your environment:
Line 46 - Hashed password file location for service account
Line 49 - Service account name. e.g. ExchangeReportServiceAccount@contoso.com
Line 53 - Update <O365TenantDomain>.onmicrosoft.com. e.g Contoso.onmicrosoft.com
Line 55 - http://<LocalExchangeServer>/PowerShell/  Update to your own local Exchange servername. e.g. http://ExchangeServer01/PowerShell/
Line 73 - Update "@<O365tenantdomain>.mail.onmicrosoft.com" e.g. "@Contoso.mail.onmicrosoft.com"
Line 105 - Update Email addresses, SMTP server, Server name



Created by: Erik Crider
Date 08/20/2020

EDIT HISTORY
09/08/2020 Edited the O365 connection string to add "?delegatedOrg=<O365TenantDomain>.onmicrosoft.com" due to an error seen on another script that prevented a proper connection to O365
#>



##		Various settings to ensure that the script can run. Allows Basic Auth, Updates the powershell Execution Policy. May not be needed in your environment
$regpath = "HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client"
$name = "AllowBasic"
$val = "1"
SET-ITEMPROPERTY -PATH $regpath -NAME $name -VALUE $val

##		Date for use with filenames.
$Date = get-date -format yyyy-MM-ddTHH-mm-ss-ff
$transcriptfile = "C:\Automation\RemoteMailbox\Logs\Transcript-" +$date +".txt"
$Filename = "C:\Automation\RemoteMailbox\Logs\RemoteMailboxJob-" +$date +".csv"

##		Get newly created mailboxes and puts into file. Set to 7 days, but can be changed below. All Mailboxes excluding shared and room mailboxes.	
$when = ((Get-Date).AddDays(-7)).Date


##		Get credentials and pass them into a variable
##		The file for the password MUST be made on the same server that this is run from
$password = get-content <automationservicePasswordhashfilelocation>txt | convertto-securestring

##		Log into O365 and then On Premise. MUST BE IN THIS ORDER. If not, the get-mailbox command will direct towards the on premise server instead of O365		
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist "<ExchangeReportServiceAccount>",$password
$UserCredential = $credentials
$sessionOption = New-PSSessionOption -SkipRevocationCheck 
##$Session365 = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection -SessionOption $sessionOption -ErrorAction SilentlyContinue
$Session365 = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid?delegatedOrg=<O365TenantDomain>.onmicrosoft.com -Credential $UserCredential -Authentication Basic -AllowRedirection -SessionOption $sessionOption -ErrorAction SilentlyContinue
Import-PSSession $Session365 -ErrorAction SilentlyContinue
$SessionOnPrem = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://<LocalExchangeServer>/PowerShell/ -Authentication Kerberos -Credential $UserCredential
Import-PSSession $SessionOnPrem -DisableNameChecking

##		File for storing values that will be emailed out later to track what changes were made or attempted.
$RemMBXOutput = @()


Get-Mailbox -ResultSize Unlimited |where {($_.whenmailboxcreated -gt $when) -and ($_.RecipientTypeDetails -ne "RoomMailbox") -and ($_.RecipientTypeDetails -ne "SharedMailbox")}| Select UserPrincipalName,Identity,Mailbox,ExchangeGuid |Export-Csv $Filename -notypeinformation
$csv = Import-Csv $Filename



##	Get objects from csv file to process.
foreach ($item in $csv) {
$mbtemp = get-remotemailbox $item.userprincipalname -erroraction silentlycontinue
if ($mbtemp -eq $Null) {

   $truncated = $item.userprincipalname -replace "........$"
$routingaddress = $Truncated + "@<O365tenantdomain>.mail.onmicrosoft.com"
Write-Host "Enabling remote Mailbox for "$Truncated  -ForegroundColor Green
enable-remotemailbox -identity $item.userprincipalname -remoteroutingaddress $routingaddress
set-remotemailbox  -identity $truncated -exchangeguid $item.exchangeguid
$RemMbx = get-remotemailbox  -identity $truncated 
$dataObject = New-Object PSObject
Add-Member -inputObject $dataObject -memberType NoteProperty -name "UserToUpdate" -value $item.userprincipalname
Add-Member -inputObject $dataObject -memberType NoteProperty -name "Name" -value $RemMBX.name
Add-Member -inputObject $dataObject -memberType NoteProperty -name "Remote Routing Address" -value $RemMBX.remoteroutingaddress
Add-Member -inputObject $dataObject -memberType NoteProperty -name "ExchangeGUID" -value $RemMBX.ExchangeGUID
$RemMBXOutput += $dataObject 
$dataObject

}
else {if ($mbtemp.exchangeguid -ne $item.exchangeguid) {
Write-Host "ExchangeGUID doesn't match. Writing GUID" $item.exchangeguid "into user" $mbtemp.userprincipalname -ForegroundColor Red
set-remotemailbox $mbtemp.userprincipalname -ExchangeGuid $item.exchangeguid
$RemMbxGUID = get-remotemailbox  -identity $item.userprincipalname
$dataObjectGUID = New-Object PSObject
Add-Member -inputObject $dataObjectGUID -memberType NoteProperty -name "UserToUpdate" -value $item.userprincipalname
Add-Member -inputObject $dataObjectGUID -memberType NoteProperty -name "Name" -value $RemMBXGUID.name
Add-Member -inputObject $dataObjectGUID -memberType NoteProperty -name "Remote Routing Address" -value $RemMBXGUID.remoteroutingaddress
Add-Member -inputObject $dataObjectGUID -memberType NoteProperty -name "ExchangeGUID" -value $RemMBXGUID.ExchangeGUID
$RemMBXOutput += $dataObjectGUID 
$dataObjectGUID

}
}
}


##		Send mail message to designated user(s) or group(s). Includes the now closed out transcript file
$RemMBXOutput | export-csv -path $transcriptfile -notypeinformation
Send-mailmessage -to <emailaddress> -from ExchangeReportService@<Domain.com> -smtpserver <SMTPServer.domain.com> -attachments $transcriptfile -Subject "Remote Mailbox Job" -Body "See attached file for users updated. If no users are in the file this is because no new mailboxes were found. This script run nightly from <server>"




