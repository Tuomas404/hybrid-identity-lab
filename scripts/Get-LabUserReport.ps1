<#
.SYNOPSIS
  Report of lab users: status, OU, groups, logon and password info.
#>
[CmdletBinding()]
param()

Import-Module ActiveDirectory -ErrorAction Stop
$lab = "OU=LAB,$((Get-ADDomain).DistinguishedName)"

Get-ADUser -Filter * -SearchBase $lab -Properties EmployeeID, MemberOf, Description, LastLogonDate, PasswordLastSet, whenCreated |
    Sort-Object EmployeeID |
    ForEach-Object {
        [pscustomobject]@{
            EmployeeId      = $_.EmployeeID
            SamAccountName  = $_.SamAccountName
            Name            = $_.Name
            Enabled         = $_.Enabled
            OU              = ($_.DistinguishedName -split ',', 2)[1]
            Groups          = (@($_.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name }) -join ', ')
            LastLogonDate   = $_.LastLogonDate
            PasswordLastSet = $_.PasswordLastSet
            Created         = $_.whenCreated
            Description     = $_.Description
        }
    }