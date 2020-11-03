<#
This script outputs the following three things into the directory you run the script from
Users with inboxrules that autoforward messages
All delegates to all mailboxes
All users with a forwarding address set

This differs from the source script found here: https://github.com/OfficeDev/O365-InvestigationTooling
	Outputs mailbox with the inboxrule so you know which mailbox the rule is set on
	Adds datetime to the file name so that you can run this multiple times without having to rename or delete your old files
	
Required PowerShell Modules
MSOnline
ExchangeOnlineShell (if using the Connect-EOShell method to connect to EXO

Author: Erik Crider
Date:	11/3/2020
#>

## This connects to Azure Active Directory
Connect-MsolService

## connect to Exchange Online
## Can also use command "Connect-EOShell" if you have the Powershell Module ExchangeOnlineShell
$userCredential = Get-Credential
$ExoSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $userCredential -Authentication Basic -AllowRedirection
Import-PSSession $ExoSession


##Variables
$allUsers = @()
$date = (get-date -uformat "%m-%d-%Y-%R" | ForEach-Object { $_ -replace ":", "." }) 
$UserInboxRules = @()
$UserDelegates = @()
$mbx = @()
foreach ($User in $allUsers){
$MBX = $User

## Get all MSOL Users where UserPrincipalName -notlike "*#EXT#*
$AllUsers = Get-MsolUser -All -EnabledFilter EnabledOnly |sort userprincipalname | select ObjectID, UserPrincipalName, FirstName, LastName, StrongAuthenticationRequirements, StsRefreshTokensValidFrom, StrongPasswordRequired, LastPasswordChangeTimestamp | Where-Object {($_.UserPrincipalName -notlike "*#EXT#*")}

## Get all inbox rules where the following attributes are not $Null: ForwardTo, ForwardAsAttachmentTo, RedirectsTo
## Copy data to new PSObject to capture the mailbox the inboxrul belongs to
Foreach ($m in $MBX)
{
    Write-Host "Checking inbox rules for user: " $M.UserPrincipalName;
    $UserInboxRule = Get-InboxRule -Mailbox $M.UserPrincipalname | Select Name, Description, Enabled, Priority, ForwardTo, ForwardAsAttachmentTo, RedirectTo, DeleteMessage | Where-Object {($_.ForwardTo -ne $null) -or ($_.ForwardAsAttachmentTo -ne $null) -or ($_.RedirectsTo -ne $null)}
    Foreach ($rule in $UserInboxRule)
    {
    
    $dataObject = New-Object PSObject
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "Mailbox" -value $M.UserPrincipalName
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "Name" -value $Rule.Name
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "Description" -value $Rule.Description
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "Enabled" -value $Rule.Enabled
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "Priority" -value $Rule.Priority
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "ForwardTo" -value $Rule.ForwardTo
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "ForwardAsAttachmentTo" -value $Rule.ForwardAsattachmentTo
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "RedirectTo" -value $Rule.RedirectTo
    Add-Member -inputObject $dataObject -memberType NoteProperty -name "DeleteMessage" -value $Rule.DeleteMessage
    $UserInboxRules += $DataObject
    }
    }
}


## Get all mailboxes with Delegated access
foreach ($User in $allUsers)
{
    Write-Host "Checking delegates for user: " $User.UserPrincipalName;
    $UserDelegates += Get-MailboxPermission -Identity $User.UserPrincipalName | Where-Object {($_.IsInherited -ne "True") -and ($_.User -notlike "*SELF*")} | select-object RunspaceId,AccessRights,Deny,InheritanceType,User,Identity,IsInherited,IsValid,ObjectState
}

## Get all mailboxes where the following attribute is not $Null: ForwardingSMTPAddress
$SMTPForwarding = Get-Mailbox -ResultSize Unlimited | select DisplayName,ForwardingAddress,ForwardingSMTPAddress,DeliverToMailboxandForward | where {$_.ForwardingSMTPAddress -ne $null}


## Output data to file. Saves in same directory you have selected in Powershell.
$UserInboxRules | Export-Csv "MailForwardingRulesToExternalDomains-$Date.csv" -NoTypeInformation
$UserDelegates | Export-Csv "MailboxDelegatePermissions-$Date.csv"  -NoTypeInformation
$SMTPForwarding | Export-Csv "Mailboxsmtpforwarding-$Date.csv"  -NoTypeInformation
