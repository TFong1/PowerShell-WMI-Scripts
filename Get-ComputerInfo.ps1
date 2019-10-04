
param (
    # Name of PC
    [Parameter(Mandatory = $True)]
    [string]
    $Computername = "."
)

Set-Variable PhysicalDrive -Option ReadOnly -Value 3
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

##########################################################################

Write-Host (Get-WmiObject -ComputerName $Computername -Class Win32_ComputerSystem).Model

############################################################################

$bios = @(Get-WmiObject -ComputerName $Computername -Class Win32_BIOS | Select-Object *).Caption
Write-Host "`nBIOS version:", $bios

###########################################################################

$os = Get-WmiObject -ComputerName $Computername -Class Win32_OperatingSystem | Select-Object *
Write-Host ""
Write-Host $os.Caption
Write-Host "    * Version:"$os.version
Write-Host "    *"$os.OSArchitecture

##############################################################################

Write-Host "`nRAM:"
$totalRAM = @(Get-WmiObject -ComputerName $Computername -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
$totalRAM = To_GB -numBytes $totalRAM
Write-Host "    *"$totalRAM" GB"

#################################################################################3

# BOOT TYPE:  Legacy, UEFI
Write-Host "`nBoot Type:"
Write-Host "    *"$(if ($null -eq ([Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computername).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecureBoot\State'))) { 'Legacy BIOS'} else { 'UEFI'})

########################################################################

Write-Host "`nVideo Card(s):"
$videoCards = @(Get-WmiObject -ComputerName $Computername -Class Win32_VideoController | Select-Object -Property Caption)
foreach ($card in $videoCards) {Write-Host "    *", $card.Caption}

########################################################################

Write-Host "`nMonitor(s):"
$monitors = @(Get-WmiObject -Namespace "root\WMI" -Class "WMIMonitorID" -ComputerName $Computername)
foreach ($mon in $monitors) {
    if ($mon.UserFriendlyNameLength -gt 0) {
        $monitorName = ConvertToString -str $mon.UserFriendlyName
    }
    else {
        $monitorName = ConvertToString -str $mon.ManufacturerName
    }
    $monitorSerialNumber = ConvertToString -str $mon.SerialNumberID
    Write-Host "    * $($monitorName) ($monitorSerialNumber)"
}

#####################################################################

Write-Host "`nDisk Drive(s):"
#$drives = @(Get-WmiObject -ComputerName $Computername -Class Win32_LogicalDisk | Select-Object -Property DeviceID, DriveType, FileSystem, FreeSpace, MediaType, Size)
$drives = @(Get-WmiObject -ComputerName $Computername -Class MSFT_PhysicalDisk -Namespace "root\Microsoft\Windows\Storage" | Select-Object *)
foreach ($hd in $drives) {
    $mediaType = DiskMediaType -mediaType $hd.MediaType
    $diskSize = To_GB -numBytes $hd.Size
    #$usedSpace = To_GB -numBytes $hd.AllocatedSize
    Write-Host "    *", $hd.FriendlyName, $mediaType, $diskSize"GB"
}

#################################################################

Write-Host "`nLogged On User(s):"
$explorerProcess = @(Get-WmiObject -ComputerName $Computername -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
$logonScreenStatus = @(Get-WmiObject -ComputerName $Computername -Query "SELECT * FROM Win32_Process WHERE Name='LogonUI.exe'" -ErrorAction SilentlyContinue).Count

if ($explorerProcess.Count -eq 0) {
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
        Write-Host "    * Phone: "$aduser.TelephoneNumber
        Write-Host "    * Employee type:"$aduser.Description
        Write-Host "    * Password expired:"$aduser.PasswordExpired
        Write-Host "    * Last Logon Date:"$aduser.LastLogonDate
        Write-Host "    * Password Last Set: $(Get-TimeString -time $aduser.pwdLastSet)"
    }
}

if ($logonScreenStatus -gt 0) {
    Write-Host "    * Logon screen : ON"
}
else {
    Write-Host "    * Logon screen : OFF"
}


############