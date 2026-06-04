# Define target paths for Public and all individual User desktops
$TargetPaths = @(
    "C:\Users\Public\Desktop\*.lnk"
    "C:\Users\*\Desktop\*.lnk"
)

# Search for any existing .lnk files
$FoundShortcuts = Get-Item -Path $TargetPaths -ErrorAction SilentlyContinue

if ($FoundShortcuts) {
    Write-Host "Detected $($FoundShortcuts.Count) unwanted .lnk shortcut(s)."
    exit 1 # Non-compliant: Triggers the Remediation script
} else {
    Write-Host "No .lnk shortcuts found. Device is compliant."
    exit 0 # Compliant: No action needed
}
