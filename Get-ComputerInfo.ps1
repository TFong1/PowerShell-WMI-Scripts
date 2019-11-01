
param (
    # Name of PC
    [Parameter(Mandatory = $True)]
    [string]
    $Computername = "."
)

Set-Variable PhysicalDrive -Option ReadOnly -Value 3
Set-Variable LocalDisk -Option ReadOnly 3
Set-Variable HDD -Option ReadOnly -Value 3
Set-Variable SSD -Option ReadOnly -Value 4

function ConvertToString {
    param( [char[]]$str )
    ($str -ne 0 | ForEach-Object {[char] $_}) -join ""
}

function To_GB {
    param( [long] $numBytes )
    [Math]::Round($numBytes / 1GB, 2)
}

function DiskMediaType {
    param( [System.Int64] $mediaType )
    if ($mediaType -eq $SSD) {
        "SSD"
    }
    elseif ($mediaType -eq $HDD) {
         "HDD"
    }
    else {$mediaType}
}

function Get-TimeString {
    param( [System.Int64] $time )
    [datetime]::FromFileTime( $time ).ToString("f")
}

###################################################################################

Write-Host (Get-WmiObject -ComputerName $Computername -Class Win32_ComputerSystem).Model

###################################################################################

$bios = @(Get-WmiObject -ComputerName $Computername -Class Win32_BIOS | Select-Object *)
Write-Host "    * BIOS version:  ", $bios.SMBIOSBIOSVersion
Write-Host "    * Serial Number: ", $bios.SerialNumber

#################################################################################

$totalRAM = @(Get-WmiObject -ComputerName $Computername -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
$totalRAM = To_GB -numBytes $totalRAM
Write-Host "    * RAM:            $totalRAM GB"

##################################################################################

# BOOT TYPE:  Legacy, UEFI
Write-Host "    * Boot Type:     "$(if ($null -eq ([Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computername).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecureBoot\State'))) { 'Legacy BIOS'} else { 'UEFI'})

#################################################################################

$os = Get-WmiObject -ComputerName $Computername -Class Win32_OperatingSystem | Select-Object *
Write-Host "`n$($os.Caption)"
Write-Host "    * Version:"$os.version
Write-Host "    *"$os.OSArchitecture

########################################################################

Write-Host "`nVideo Card(s):"
$videoCards = @(Get-WmiObject -ComputerName $Computername -Class Win32_VideoController)
foreach ($card in $videoCards) {Write-Host "    * $($card.Caption) : $($card.VideoModeDescription)"}

########################################################################

Write-Host "`nMonitor(s):"
$monitorIDs = Get-WmiObject -Namespace "root\WMI" -Class "WMIMonitorID" -ComputerName $Computername
$availMonrRes = Get-WmiObject -Namespace "root\WMI" -Class "WMIMonitorListedSupportedSourceModes" -ComputerName $Computername

$results = foreach ($res in $availMonrRes) {
    # Get current monitor ID
    $mon = $monitorIDs | Where-Object { $_.InstanceName -eq $res.InstanceName }

    # Sort available resolutions by display area (width*height)
    $sortedResolutions = $res.MonitorSourceModes | Sort-Object -Property { $_.HorizontalActivePixels * $_.VerticalActivePixels }
    $maxResolutions = $sortedResolutions | Select-Object @{ N="MaxRes"; E={"$($_.HorizontalActivePixels)x$($_.VerticalActivePixels)"}}

    # Organize output, select the maximum resolution for each monitor
    [PSCustomObject]@{
        Name = ( ConvertToString -str $mon.UserFriendlyName )
        Resolution = ( $maxResolutions | Select-Object -Last 1 ).MaxRes
        SerialNumber = ( ConvertToString -str $mon.SerialNumberID )
    }
}

foreach ($mon in $results) { Write-Host "    * $($mon.Name) : $($mon.Resolution) ($($mon.SerialNumber))" }

<# 
foreach ($mon in $monitors) {
    if ($mon.UserFriendlyNameLength -gt 0) {
        $monitorName = ConvertToString -str $mon.UserFriendlyName
    }
    else {
        $monitorManufacturer = ConvertToString -str $mon.ManufacturerName
        $monitorProductCode = ConvertToString -str $mon.ProductCodeID
        $monitorName = "$monitorManufacturer $monitorProductCode"
    }
    $serialNumber = ConvertToString -str $mon.SerialNumberID
    Write-Host "    * $($monitorName.Trim()) ( S/N: $serialNumber )"
}
 #>

#####################################################################

Write-Host "`nDisk Drive(s):"
$drives = @(Get-WmiObject -ComputerName $Computername -Class MSFT_PhysicalDisk -Namespace "root\Microsoft\Windows\Storage" | Select-Object *)
foreach ($hd in $drives) {
    $mediaType = DiskMediaType -mediaType $hd.MediaType
    $diskSize = To_GB -numBytes $hd.Size
    Write-Host "    * $($hd.FriendlyName)   ($mediaType)   $($diskSize)GB"
}

$drives = @(Get-WmiObject -ComputerName $Computername -Class Win32_LogicalDisk | Select-Object -Property DeviceID, DriveType, FileSystem, FreeSpace, MediaType, Size)
foreach ($hd in $drives) {
    if ($hd.DriveType -eq $LocalDisk) {
        $freespace = To_GB -numBytes $hd.FreeSpace
        Write-Host "    * $($hd.DeviceID)   $($freespace)GB Free"
    }
}

#################################################################

Write-Host "`nLogged On User(s):"
$explorerProcess = @(Get-WmiObject -ComputerName $Computername -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
$logonScreenStatus = @(Get-WmiObject -ComputerName $Computername -Query "SELECT * FROM Win32_Process WHERE Name='LogonUI.exe'" -ErrorAction SilentlyContinue).Count

if (0 -eq $explorerProcess.Count) {
    Write-Host "No explorer.exe process found / Nobody interactively logged in."
}
else {
    foreach ($user in $explorerProcess) {
        $username = $user.GetOwner().User
        $domain = $user.GetOwner().Domain
        $aduser = Get-ADUser -Filter {Name -eq $username} -Server "ad.server.domain" -Properties *
        #$firstname = $aduser.GivenName
        #$lastname = $aduser.Surname
        $name = $aduser.DisplayName
        Write-Host "    * $domain\$username ($name) logged on since: $($user.ConvertToDateTime($user.CreationDate).ToString("f"))"
        Write-Host "         - Office Phone: "$aduser.OfficePhone
        Write-Host "         - Employee type:"$aduser.Description
        Write-Host "         - Password expired:"$aduser.PasswordExpired
        Write-Host "         - Last Logon Date:"$aduser.LastLogonDate

        if ((0 -eq $aduser.pwdLastSet) -or ([datetime]::MaxValue.Ticks -le $aduser.pwdLastSet)) {
            $pwdLastSet = "         - Password never expires"
        }
        else {
            $pwdLastSet = Get-TimeString -time $aduser.pwdLastSet
        }
        Write-Host "         - Password Last Set: $pwdLastSet"
    }
}

if (0 -lt $logonScreenStatus) {
    Write-Host "    * Logon screen : ON"
}
else {
    Write-Host "    * Logon screen : OFF"
}

####################################################################
