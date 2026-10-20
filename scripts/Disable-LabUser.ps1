<#
.SYNOPSIS
  Offboarding: disables lab users by EmployeeId.
.DESCRIPTION
  For each EmployeeId: disable account, stamp description with date,
  remove group memberships, move to OU=Disabled. Idempotent. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string[]]$EmployeeId
)

Import-Module ActiveDirectory -ErrorAction Stop

$domainDN   = (Get-ADDomain).DistinguishedName
$searchBase = "OU=LAB,$domainDN"
$disabledOU = "OU=Disabled,OU=LAB,$domainDN"
$today      = Get-Date -Format 'yyyy-MM-dd'

foreach ($id in $EmployeeId) {
    $result = [pscustomobject]@{
        EmployeeId     = $id
        SamAccountName = $null
        Status         = $null
        Actions        = $null
        RemovedGroups  = $null
        Message        = $null
    }

    try {
        # Search only under OU=LAB so built-in accounts can never be hit
        $users = @(Get-ADUser -Filter "EmployeeID -eq '$id'" -SearchBase $searchBase -Properties EmployeeID, MemberOf, Description)

        if ($users.Count -eq 0) { $result.Status = 'NotFound'; $result; continue }
        if ($users.Count -gt 1) {
            $result.Status  = 'Failed'
            $result.Message = "EmployeeId found $($users.Count) times"
            $result; continue
        }

        $u = $users[0]
        $result.SamAccountName = $u.SamAccountName
        $groupNames   = @($u.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name })
        $inDisabledOU = $u.DistinguishedName -like "*,$disabledOU"

        # Collect only the steps that are still missing (idempotency)
        $actions = @()
        if ($u.Enabled)              { $actions += 'Disable' }
        if ($groupNames.Count -gt 0) { $actions += 'RemoveGroups' }
        if (-not $inDisabledOU)      { $actions += 'MoveToDisabled' }

        if ($actions.Count -eq 0) { $result.Status = 'AlreadyDone'; $result; continue }

        $result.Actions       = $actions -join ', '
        $result.RemovedGroups = $groupNames -join ', '

        if ($PSCmdlet.ShouldProcess($u.SamAccountName, "Offboard ($($result.Actions))")) {
            if ($u.Enabled) {
                Disable-ADAccount -Identity $u.ObjectGUID
                $desc = "Disabled $today (offboarding)"
                if ($u.Description) { $desc = "$desc | $($u.Description)" }
                Set-ADUser -Identity $u.ObjectGUID -Description $desc
            }
            if ($groupNames.Count -gt 0) {
                Remove-ADPrincipalGroupMembership -Identity $u.ObjectGUID -MemberOf $u.MemberOf -Confirm:$false
            }
                        if (-not $inDisabledOU) {
                # CN must be unique within one OU: rename first if the name is taken in OU=Disabled
                $cnTaken = Get-ADObject -Filter "Name -eq '$($u.Name)'" -SearchBase $disabledOU -SearchScope OneLevel
                if ($cnTaken) {
                    Rename-ADObject -Identity $u.ObjectGUID -NewName "$($u.Name) ($id)"
                }
                Move-ADObject -Identity $u.ObjectGUID -TargetPath $disabledOU
            }
            $result.Status = 'Offboarded'
        }
        else {
            $result.Status = 'WhatIf'
        }
    }
    catch {
        $result.Status  = 'Failed'
        $result.Message = $_.Exception.Message
    }
    $result
}