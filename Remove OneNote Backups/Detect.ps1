$backupPath = Join-Path $env:LOCALAPPDATA 'Microsoft\OneNote\16.0\Backup'
if (Test-Path -LiteralPath $backupPath) {
    Write-Output "Backup folder found: $backupPath"
    Exit 1  # Not compliant
} else {
    Write-Output "Backup folder not found."
    Exit 0  # Compliant
}