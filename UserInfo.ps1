#
#  User Info
#  Param:  User's W+ID

param (
    # User's employee ID
    [Parameter(Mandatory = $true)]
    [string]
    $userid = ""    # get current user's id
)

function Get-TimeString {
    param( [System.Int64] $time )
    [datetime]::FromFileTime( $time ).ToLocalTime().ToString("f")
}

$user = Get-ADUser -Filter { Name -eq $userid } -Server "ad.server.domain" -Properties * | Select-Object *

Write-Host $user.DisplayName
Write-Host $user.Description
Write-Host "Office Phone: $($user.OfficePhone) "

if ((0 -eq $user.accountExpires) -or ([datetime]::MaxValue.Ticks -le $user.accountExpires)) {
    Write-Host "* Account Never Expires"
}
else {
    $accountExpires = Get-TimeString -time $user.accountExpires
    Write-Host "* Account Expires: $($accountExpires) "
}

if ((0 -eq $user.LockoutTime) -or ([datetime]::MaxValue.Ticks -le $user.LockoutTime)) {
    Write-Host "* User NOT locked out"
}
else {
    $lockoutTime = Get-TimeString -time $user.LockoutTime
    Write-Host "* Lockout Time: $($lockoutTime) "
}

if ( $null -ne $user.LockoutDuration ) {
    $timespan = New-TimeSpan -Seconds ([int]($user.LockoutDuration / 10e10))
    Write-Host "* Lockout Duration: $($timespan.TotalMinutes) minutes"
}

Write-Host "* Last Logon Date: $($user.LastLogonDate.ToString('f')) "
Write-Host "* Password Expired: $($user.PasswordExpired) "
Write-Host "* Password Last Set: $($user.PasswordLastSet.ToString('f')) "
