<#
.SYNOPSIS
  Delegates password reset and account unlock on user objects under OU=Users to SG-Role-HelpDesk.
.DESCRIPTION
  Adds three inheritable ACEs on OU=Users, applied to user objects only:
  Reset Password, read/write pwdLastSet, read/write lockoutTime. Idempotent. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GroupName = 'SG-Role-HelpDesk'
)

Import-Module ActiveDirectory -ErrorAction Stop

$domainDN = (Get-ADDomain).DistinguishedName
$ouDN     = "OU=Users,OU=LAB,$domainDN"
$adPath   = "AD:\$ouDN"
$sid      = (Get-ADGroup -Identity $GroupName).SID

# Schema GUIDs (identical in every AD forest)
$guidUser          = [guid]'bf967aba-0de6-11d0-a285-00aa003049e2'  # class: user
$guidResetPassword = [guid]'00299570-246d-11d0-a768-00aa006e0529'  # extended right: Reset Password
$guidPwdLastSet    = [guid]'bf967a0a-0de6-11d0-a285-00aa003049e2'  # attribute: pwdLastSet (force change at next logon)
$guidLockoutTime   = [guid]'28630ebf-41d5-11d1-a9c1-0000f80367c1'  # attribute: lockoutTime (unlock)

$rw = [System.DirectoryServices.ActiveDirectoryRights]'ReadProperty, WriteProperty'
$wanted = @(
    @{ Name = 'Reset Password';    Rights = [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight; Guid = $guidResetPassword }
    @{ Name = 'Write pwdLastSet';  Rights = $rw; Guid = $guidPwdLastSet }
    @{ Name = 'Write lockoutTime'; Rights = $rw; Guid = $guidLockoutTime }
)

$acl      = Get-Acl -Path $adPath
$existing = $acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])

$results = foreach ($w in $wanted) {
    $found = $existing | Where-Object {
        $_.IdentityReference -eq $sid -and
        $_.ActiveDirectoryRights -eq $w.Rights -and
        $_.ObjectType -eq $w.Guid -and
        $_.InheritedObjectType -eq $guidUser -and
        $_.AccessControlType -eq 'Allow'
    }
    $status = 'Exists'
    if (-not $found) {
        $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid, $w.Rights, 'Allow', $w.Guid, 'Descendents', $guidUser)
        $acl.AddAccessRule($rule)
        $status = 'Missing'
    }
    [pscustomobject]@{ Permission = $w.Name; Status = $status }
}

$missing = @($results | Where-Object Status -eq 'Missing')
if ($missing.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($ouDN, "Grant $GroupName - $($missing.Permission -join ', ')")) {
        Set-Acl -Path $adPath -AclObject $acl
        $missing | ForEach-Object { $_.Status = 'Added' }
    }
    else {
        $missing | ForEach-Object { $_.Status = 'WhatIf' }
    }
}
$results