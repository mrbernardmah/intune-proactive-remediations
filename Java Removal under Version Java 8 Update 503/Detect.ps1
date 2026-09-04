# ==============================================================================
# Detection Script: Detect Java (32-bit & 64-bit) older than 8.0.5030.01
# Exit 0 = Compliant (No outdated Java found)
# Exit 1 = Non-Compliant (Outdated Java found, triggers remediation)
# ==============================================================================

$TargetVersion = [version]"8.0.5030.01"

# Query both 64-bit and 32-bit registry uninstall keys
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$OutdatedJava = Get-ItemProperty -Path $RegistryPaths -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.DisplayName -like "*Java*" -or $_.DisplayName -like "*SE Development Kit*") -and
        $_.DisplayVersion
    } |
    Where-Object {
        try {
            [version]$_.DisplayVersion -lt $TargetVersion
        } catch {
            $false
        }
    }

if ($OutdatedJava) {
    $foundVersions = ($OutdatedJava | ForEach-Object { "$($_.DisplayName) ($($_.DisplayVersion))" }) -join "; "
    Write-Output "Non-Compliant: Outdated Java version(s) detected: $foundVersions"
    exit 1
} else {
    Write-Output "Compliant: No Java versions older than $TargetVersion detected."
    exit 0
}