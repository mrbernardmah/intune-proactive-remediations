# 1. Terminate running processes for all target apps
# Added "OneDrive" to the process list
$processNames = @("ms-teams", "Teams", "Vivi", "ONENOTEM", "ONENOTE", "OneDrive")

foreach ($process in $processNames) {
    if (Get-Process -Name $process -ErrorAction SilentlyContinue) {
        Stop-Process -Name $process -Force -Verbose
        Write-Host "Terminated running process: $process" -ForegroundColor Yellow
    }
}

# Target registry and shortcut names for the current user
# Added "OneDrive" to both registry and shortcut targets
$registryTargets = @("Teams", "electron.app.Vivi", "OneDrive")
$shortcutTargets = @("Send to OneNote Tool", "OneNote2010", "Microsoft Office OneNote Quick Launch", "Send to OneNote", "OneDrive")

# 2. Clean Registry Startup Items (Current User Only)
$hkcuRunPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
foreach ($app in $registryTargets) {
    if (Get-ItemProperty -Path $hkcuRunPath -Name $app -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $hkcuRunPath -Name $app -Verbose
        Write-Host "Successfully removed $app from HKCU Run registry key." -ForegroundColor Green
    }
}

# 3. Clean Legacy Shortcuts from the User's Startup Folder
$userStartupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

if (Test-Path $userStartupFolder) {
    foreach ($target in $shortcutTargets) {
        # Find any .lnk files matching the target names in user profile
        $shortcuts = Get-ChildItem -Path $userStartupFolder -Filter "*$target*.lnk" -ErrorAction SilentlyContinue
        foreach ($file in $shortcuts) {
            Remove-Item -Path $file.FullName -Force -Verbose
            Write-Host "Deleted user startup shortcut: $($file.Name)" -ForegroundColor Green
        }
    }
}