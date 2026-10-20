# New-LabGroups.ps1 - creates security groups in OU=Groups
# Safe to run again: existing groups are skipped.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$groupsOU = "OU=Groups,OU=LAB,$((Get-ADDomain).DistinguishedName)"

$groups = @(
    @{ Name = 'SG-Dept-HR';       Description = 'Department: HR' }
    @{ Name = 'SG-Dept-IT';       Description = 'Department: IT' }
    @{ Name = 'SG-Dept-Sales';    Description = 'Department: Sales' }
    @{ Name = 'SG-Role-HelpDesk'; Description = 'Can reset passwords and unlock users in OU=Users' }
)

foreach ($g in $groups) {
    if (Get-ADGroup -Filter "Name -eq '$($g.Name)'") {
        Write-Host "Exists:  $($g.Name)"
    } else {
        New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope Global `
            -GroupCategory Security -Path $groupsOU -Description $g.Description
        Write-Host "Created: $($g.Name)"
    }
}

Write-Host "`nGroups in ${groupsOU}:"
Get-ADGroup -SearchBase $groupsOU -Filter * |
    Sort-Object Name |
    Format-Table Name, GroupScope, GroupCategory -AutoSize