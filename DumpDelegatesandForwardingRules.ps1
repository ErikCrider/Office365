<#
This script outputs the following three things into the directory you run the script from
Users with inboxrules that autoforward messages
All delegates to all mailboxes
All users with a forwarding address set
This differs from the source script found here: https://github.com/OfficeDev/O365-InvestigationTooling
	Only grabs Mailboxes, not MSOL users as this is all that is needed, and takes less time
    Added Progress bar
    Outputs MailboxOwnerID with the inboxrule so you know which mailbox the rule is set on
    Pulls SMTP Forwards from variable for faster results
    Adds datetime to the file name so that you can run this multiple times without having to rename or delete your old files
	
Required PowerShell Modules
ExchangeOnlineShell (if using the Connect-EOShell method to connect to EXO
Author: Erik Crider
Date:	11/3/2020

Updated 12/8/2020
Only grabs Mailboxes, not MSOL users as this is all that is needed, and takes less time
Added Progress bar to longest running portion of script. No longer displays inline for cleaner output
Pulls SMTP Forwards from variable for faster results
Added output path
#>

##Variables
$OutputPath = "c:\temp\" ## Change to desired output directory
$date = (get-date -uformat "%m-%d-%Y-%R" | ForEach-Object { $_ -replace ":", "." }) 
$UserInboxRules = @()
$UserDelegates = @()
$SMTPForwarding = @()
$AllMBXPerms = @()
$UserDelegates = @()


## connect to Exchange Online
## Can also use command "Connect-EOShell" if you have the Powershell Module ExchangeOnlineShell
$userCredential = Get-Credential
$ExoSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $userCredential -Authentication Basic -AllowRedirection
Import-PSSession $ExoSession


## Get all Mailboxes
Write-Host "Getting all mailboxes"
$AllMBX = get-mailbox -resultsize unlimited

## Get all inbox rules where the following attributes are not $Null: ForwardTo, ForwardAsAttachmentTo, RedirectsTo
Foreach ($user in $AllMBX){
$UserInboxRules += Get-InboxRule -Mailbox $User.userprincipalname | Select MailboxOwnerId, Name, Description, Enabled, Priority, ForwardTo, ForwardAsAttachmentTo, RedirectTo, DeleteMessage | Where-Object {($_.ForwardTo -ne $null) -or ($_.ForwardAsAttachmentTo -ne $null) -or ($_.RedirectsTo -ne $null)}
[int]$CurrentItem = [array]::indexof($AllMBX,$User)
Write-Progress -Activity "Getting Rules And Delegates" -Status "Mailbox $($CurrentItem) of $($ALLMBX.Count - 1) - $([math]::round((($CurrentItem + 1)/$AllMBX.Count),2) * 100)%  - Currently checking - $($User.Name)" -PercentComplete $([float](($CurrentItem + 1)/$AllMBX.Count) * 100)
}

## Get all mailboxes with Delegated access
Write-Host "Getting all mailbox permissions"
$AllMBXPerms = Get-MailboxPermission -ResultSize Unlimited -Identity *
$UserDelegates = $AllMBXPerms | Where-Object {($_.IsInherited -ne "True") -and ($_.User -notlike "NT AUTHORITY\SELF") -and ($_.User -notlike "NT AUTHORITY\SYSTEM")} | select-object RunspaceId,AccessRights,Deny,InheritanceType,User,Identity,IsInherited,IsValid,ObjectState

## Get all mailboxes where the following attribute is not $Null: ForwardingSMTPAddress
Foreach ($Mbx in $allMBX){
$SMTPForwarding += $AllMBX | where {$_ -eq $mbx} | select DisplayName,ForwardingAddress,ForwardingSMTPAddress,DeliverToMailboxandForward | where {$_.ForwardingSMTPAddress -ne $null}
}

## Output data to file. Saves in same directory you have selected in Powershell.
$UserInboxRules | Export-Csv $Outputpath"MailForwardingRulesToExternalDomains-$Date.csv" -NoTypeInformation
$UserDelegates | Export-Csv $Outputpath"MailboxDelegatePermissions-$Date.csv"  -NoTypeInformation
$SMTPForwarding | Export-Csv $Outputpath"Mailboxsmtpforwarding-$Date.csv"  -NoTypeInformation
Write-host "Files output to $Outputpath"
