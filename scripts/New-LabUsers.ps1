# New-LabUsers.ps1 - onboarding: creates AD users from CSV rows
# Input columns: EmployeeId, FirstName, LastName, Department, Title
# Safe to run again: users are matched by EmployeeId and skipped if found.
param(
    [Parameter(Mandatory)]
    [object[]]$Users
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domain    = Get-ADDomain
$usersOU   = "OU=Users,OU=LAB,$($domain.DistinguishedName)"
$upnSuffix = $domain.DNSRoot                      # lab.test
$rng       = [System.Security.Cryptography.RandomNumberGenerator]::Create()

function ConvertTo-AsciiName {
    # Strips accents (umlaut a -> a), lowercases, keeps only a-z 0-9 . -
    param([string]$Text)
    $decomposed = $Text.Normalize([Text.NormalizationForm]::FormD)
    $chars = $decomposed.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
    }
    ((-join $chars).ToLower()) -replace '[^a-z0-9.-]', ''
}

function Get-SecureRandomChar {
    param([string]$Chars)
    $bytes = New-Object byte[] 4
    $rng.GetBytes($bytes)
    $Chars[[BitConverter]::ToUInt32($bytes, 0) % $Chars.Length]
}

function New-RandomPassword {
    # 16 chars with upper, lower, digit and symbol (meets AD complexity)
    $sets  = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!#%+=?'
    $all   = -join $sets
    $chars = @(foreach ($s in $sets) { Get-SecureRandomChar $s })
    $chars += @(1..12 | ForEach-Object { Get-SecureRandomChar $all })
    -join ($chars | Get-Random -Count $chars.Count)   # shuffle positions
}

function Get-UniqueSam {
    # sAMAccountName max 20 chars; adds 2, 3, ... if the name is taken
    param([string]$Base)
    $candidate = $Base.Substring(0, [Math]::Min(20, $Base.Length))
    $n = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'") {
        $n++
        $suffix    = [string]$n
        $candidate = $Base.Substring(0, [Math]::Min(20 - $suffix.Length, $Base.Length)) + $suffix
    }
    $candidate
}

foreach ($u in $Users) {
    try {
        $existing = Get-ADUser -Filter "EmployeeID -eq '$($u.EmployeeId)'"
        if ($existing) {
            [pscustomobject]@{ EmployeeId = $u.EmployeeId; SamAccountName = $existing.SamAccountName
                               Status = 'Exists'; InitialPassword = $null }
            continue
        }

        $path = "OU=$($u.Department),$usersOU"
        $sam  = Get-UniqueSam -Base ('{0}.{1}' -f (ConvertTo-AsciiName $u.FirstName), (ConvertTo-AsciiName $u.LastName))

        # Object name must be unique inside one OU
        $cn = "$($u.FirstName) $($u.LastName)"
        if (Get-ADUser -Filter "Name -eq '$cn'" -SearchBase $path -SearchScope OneLevel) { $cn = "$cn ($sam)" }

        $password = New-RandomPassword
        $params = @{
            Name                  = $cn
            GivenName             = $u.FirstName
            Surname               = $u.LastName
            DisplayName           = "$($u.FirstName) $($u.LastName)"
            SamAccountName        = $sam
            UserPrincipalName     = "$sam@$upnSuffix"
            EmployeeID            = $u.EmployeeId
            Department            = $u.Department
            Title                 = $u.Title
            Path                  = $path
            AccountPassword       = (ConvertTo-SecureString $password -AsPlainText -Force)
            ChangePasswordAtLogon = $true
            Enabled               = $true
        }
        New-ADUser @params
        Add-ADGroupMember -Identity "SG-Dept-$($u.Department)" -Members $sam

        [pscustomobject]@{ EmployeeId = $u.EmployeeId; SamAccountName = $sam
                           Status = 'Created'; InitialPassword = $password }
    }
    catch {
        [pscustomobject]@{ EmployeeId = $u.EmployeeId; SamAccountName = $null
                           Status = "Failed: $($_.Exception.Message)"; InitialPassword = $null }
    }
}