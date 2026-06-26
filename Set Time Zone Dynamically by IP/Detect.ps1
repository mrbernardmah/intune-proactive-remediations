$PackageName = "Detect-TimeZoneByIPAddress"
Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$PackageName-script.log" -Force -Append

try {
    # 1. Get current system time zone
    $currentSystemTZ = (Get-TimeZone).Id
    Write-Output "Current System Time Zone: $currentSystemTZ"

    # 2. Fetch expected IANA time zone from IP
    Write-Output "Fetching IANA time zone from ipinfo.io..."
    $ianaTz = (Invoke-RestMethod -Uri "http://ipinfo.io/json").timezone
    if (-not $ianaTz) { throw "Could not retrieve IANA time zone from ipinfo.io." }
    Write-Output "Detected IANA Time Zone: $ianaTz"

    # 3. Download the XML mapping
    Write-Output "Downloading custom XML mapping..."
    $xmlUrl = "https://raw.githubusercontent.com/FlorianSLZ/scloud/refs/heads/main/scripts/Set-TimeZoneByIPAddress/windowsZones.xml"
    [xml]$windowsZones = Invoke-RestMethod -Uri $xmlUrl
    if (-not $windowsZones) { throw "Failed to download or parse the XML mapping file." }

    # 4. Map IANA to Windows Time Zone
    $mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
        $_.type -split ' ' -contains $ianaTz
    }
    if (-not $mapping) { throw "No mapping found for IANA time zone: $ianaTz" }
    $expectedWindowsTZ = $mapping.other | Select-Object -First 1
    Write-Output "Expected Windows Time Zone: $expectedWindowsTZ"

    # 5. Compare and exit accordingly
    if ($currentSystemTZ -eq $expectedWindowsTZ) {
        Write-Output "Compliant: System time zone matches IP location."
        Stop-Transcript
        Exit 0 # 0 = Compliant (Intune takes no action)
    } else {
        Write-Warning "Non-Compliant: System time zone ($currentSystemTZ) does not match expected ($expectedWindowsTZ)."
        Stop-Transcript
        Exit 1 # 1 = Non-Compliant (Triggers Remediation)
    }

} catch {
    Write-Error "Detection failed: $_"
    Stop-Transcript
    Exit 1 # Fail safe: trigger remediation if detection script fails
}