# Define target paths for Public and all individual User desktops
$TargetPaths = @(
    "C:\Users\Public\Desktop\*.lnk"
    "C:\Users\*\Desktop\*.lnk"
)

# Fetch all matching shortcut items
$ShortcutsToRemove = Get-Item -Path $TargetPaths -ErrorAction SilentlyContinue

if ($ShortcutsToRemove) {
    foreach ($Shortcut in $ShortcutsToRemove) {
        try {
            Remove-Item -Path $Shortcut.FullName -Force -ErrorAction Stop
            Write-Host "Successfully removed: $($Shortcut.FullName)"
        }
        catch {
            Write-Warning "Failed to remove: $($Shortcut.FullName). Error: $($_.Exception.Message)"
        }
    }
} else {
    Write-Host "No shortcuts found to remediate."
}
