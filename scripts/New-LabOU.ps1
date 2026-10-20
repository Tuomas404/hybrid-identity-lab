# New-LabOU.ps1 - creates the OU structure for lab.test
# Safe to run again: existing OUs are skipped.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName      # DC=lab,DC=test
$rootDN   = "OU=LAB,$domainDN"

function New-OUIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'") {
        Write-Host "Exists:  $dn"
    } else {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "Created: $dn"
    }
}

# Root OU first, then children in order (parent before child)
New-OUIfMissing -Name 'LAB' -Path $domainDN

$ous = @(
    @{ Name = 'Users';           Parent = $rootDN }
    @{ Name = 'HR';              Parent = "OU=Users,$rootDN" }
    @{ Name = 'IT';              Parent = "OU=Users,$rootDN" }
    @{ Name = 'Sales';           Parent = "OU=Users,$rootDN" }
    @{ Name = 'Computers';       Parent = $rootDN }
    @{ Name = 'Workstations';    Parent = "OU=Computers,$rootDN" }
    @{ Name = 'Servers';         Parent = "OU=Computers,$rootDN" }
    @{ Name = 'Groups';          Parent = $rootDN }
    @{ Name = 'ServiceAccounts'; Parent = $rootDN }
    @{ Name = 'Disabled';        Parent = $rootDN }
)

foreach ($ou in $ous) {
    New-OUIfMissing -Name $ou.Name -Path $ou.Parent
}

Write-Host "`nOU structure under ${rootDN}:"
Get-ADOrganizationalUnit -SearchBase $rootDN -Filter * |
    Sort-Object DistinguishedName |
    Select-Object -ExpandProperty DistinguishedName