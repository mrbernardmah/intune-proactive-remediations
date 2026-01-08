$backupPath = Join-Path $env:LOCALAPPDATA 'Microsoft\OneNote\16.0\Backup'
if (Test-Path -LiteralPath $backupPath) {
    try {
        Remove-Item -LiteralPath $backupPath -Recurse -Force
        Write-Output "Removed OneNote backup folder: $backupPath"
        Exit 0
    } catch {
        Write-Warning "Failed to remove backup folder: $($_.Exception.Message)"
        Exit 1
    }
} else {
    Write-Output "Backup folder not present; no action required."
    Exit 0
}