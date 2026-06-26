$PackageName = "Remediate-TimeZoneByIPAddress"
Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$PackageName-script.log" -Force -Append

try {
    Write-Output "Fetching IANA time zone from ipinfo.io..."
    $ianaTz = (Invoke-RestMethod -Uri "http://ipinfo.io/json").timezone
    if (-not $ianaTz) { throw "Could not retrieve IANA time zone from ipinfo.io." }

    Write-Output "Downloading custom XML mapping..."
    $xmlUrl = "https://raw.githubusercontent.com/FlorianSLZ/scloud/refs/heads/main/scripts/Set-TimeZoneByIPAddress/windowsZones.xml"
    [xml]$windowsZones = Invoke-RestMethod -Uri $xmlUrl
    if (-not $windowsZones) { throw "Failed to download or parse the XML mapping file." }

    $mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
        $_.type -split ' ' -contains $ianaTz
    }
    if (-not $mapping) { throw "No mapping found for IANA time zone: $ianaTz" }

    $windowsTZ = $mapping.other | Select-Object -First 1
    Write-Output "Target Windows Time Zone determined: $windowsTZ"

    Write-Output "Setting Windows time zone using Set-TimeZone..."
    Set-TimeZone -Id $windowsTZ
    Write-Output "Successfully updated Windows Time Zone to: $windowsTZ"
    
    Stop-Transcript
    Exit 0 # Remediation successful

} catch {
    Write-Error "Remediation failed: $_"
    Stop-Transcript
    Exit 1 # Remediation failed
}