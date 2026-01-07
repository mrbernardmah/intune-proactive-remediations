# Get the current Wi-Fi SSID from netsh
$wifiInfo = netsh wlan show interfaces

# Find the SSID line, ignoring BSSID
$ssidLine = $wifiInfo | Where-Object { $_ -match '^\s*SSID\s*:' -and $_ -notmatch 'EnterInSSID' }

# Extract SSID, trim all whitespace, remove hidden characters, convert to lowercase
$CurrentSSID = ""
if ($ssidLine) {
    $CurrentSSID = ($ssidLine -split ":",2)[1] -replace '\s','' -replace '[^\w\d]',''
    $CurrentSSID = $CurrentSSID.ToLower()
}

# Detection logic (exit 1 if WiFi, else exit 0)
if ($CurrentSSID -eq "WiFi") {
    exit 1
} else {
    exit 0
}
