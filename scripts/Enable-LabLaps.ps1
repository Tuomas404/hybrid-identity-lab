<#
.SYNOPSIS
  Enables Windows LAPS for the lab workstations, with password backup to Active Directory.
.DESCRIPTION
  1. Extends the AD schema for Windows LAPS if the attributes are missing.
  2. Lets computers in OU=Workstations write their own LAPS password to AD.
  3. Creates the GPO LAB-Workstations-LAPS, sets the LAPS policy and links it to OU=Workstations.
  LAPS creates and manages its own local admin account (automatic account management,
  Windows 11 24H2 / Windows Server 2025 or later). Passwords are passphrases, rotated every 30 days.
  Idempotent. Supports -WhatIf. Run on the DC as a member of Domain Admins and Schema Admins.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GpoName     = 'LAB-Workstations-LAPS',
    [string]$AccountName = 'WLapsAdmin'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy

$domainDN = (Get-ADDomain).DistinguishedName
$ouDN     = "OU=Workstations,OU=Computers,OU=LAB,$domainDN"
$key      = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'  # LAPS Group Policy root

# LAPS policy (values: learn.microsoft.com, "Configure policy settings for Windows LAPS")
$settings = [ordered]@{
    BackupDirectory                         = 2             # 2 = Active Directory
    PasswordAgeDays                         = 30
    PasswordComplexity                      = 6             # 6 = passphrase (long words)
    PassphraseLength                        = 6             # words
    AutomaticAccountManagementEnabled       = 1
    AutomaticAccountManagementTarget        = 1             # 1 = create and manage a new account
    AutomaticAccountManagementNameOrPrefix  = $AccountName
    AutomaticAccountManagementEnableAccount = 1             # default 0 = account is disabled
}

function New-Result([string]$Step, [string]$Status) {
    [pscustomobject]@{ Step = $Step; Status = $Status }
}

# 1. Schema
$schemaNC = (Get-ADRootDSE).schemaNamingContext
if (Get-ADObject -SearchBase $schemaNC -Filter "lDAPDisplayName -eq 'msLAPS-Password'") {
    New-Result 'Schema' 'Exists'
}
elseif ($PSCmdlet.ShouldProcess('AD schema', 'Add Windows LAPS attributes')) {
    Update-LapsADSchema -Confirm:$false
    New-Result 'Schema' 'Updated'
}
else { New-Result 'Schema' 'WhatIf' }

# 2. Computers may write their own password (re-adding the same ACE changes nothing)
if ($PSCmdlet.ShouldProcess($ouDN, 'Grant computer self-permission for LAPS')) {
    Set-LapsADComputerSelfPermission -Identity $ouDN | Out-Null
    New-Result 'SelfPermission' 'Set'
}
else { New-Result 'SelfPermission' 'WhatIf' }

# 3. GPO
try   { $gpo = Get-GPO -Name $GpoName }
catch { $gpo = $null }

if ($gpo) {
    New-Result "GPO $GpoName" 'Exists'
}
elseif ($PSCmdlet.ShouldProcess($GpoName, 'Create GPO')) {
    $gpo = New-GPO -Name $GpoName -Comment 'Windows LAPS for workstations, backup to AD'
    New-Result "GPO $GpoName" 'Created'
}
else { New-Result "GPO $GpoName" 'WhatIf' }

# 4. Policy values (only the ones that differ are written)
foreach ($name in $settings.Keys) {
    $value = $settings[$name]
    $type  = if ($value -is [string]) { 'String' } else { 'DWord' }

    $current = $null
    if ($gpo) {
        try   { $current = (Get-GPRegistryValue -Guid $gpo.Id -Key $key -ValueName $name).Value }
        catch { $current = $null }
    }

    if ($null -ne $current -and "$current" -eq "$value") {
        New-Result "Setting $name" 'Exists'
    }
    elseif ($gpo -and $PSCmdlet.ShouldProcess("$GpoName : $name = $value", 'Set policy value')) {
        Set-GPRegistryValue -Guid $gpo.Id -Key $key -ValueName $name -Type $type -Value $value | Out-Null
        New-Result "Setting $name" 'Set'
    }
    else { New-Result "Setting $name" 'WhatIf' }
}

# 5. Link to OU=Workstations
$linked = (Get-GPInheritance -Target $ouDN).GpoLinks | Where-Object DisplayName -eq $GpoName
if ($linked) {
    New-Result 'Link OU=Workstations' 'Exists'
}
elseif ($gpo -and $PSCmdlet.ShouldProcess($ouDN, "Link GPO $GpoName")) {
    New-GPLink -Guid $gpo.Id -Target $ouDN -LinkEnabled Yes | Out-Null
    New-Result 'Link OU=Workstations' 'Linked'
}
else { New-Result 'Link OU=Workstations' 'WhatIf' }
