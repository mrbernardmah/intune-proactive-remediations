# Added "OneDrive" to registry targets
$registryTargets = @("Teams", "electron.app.Vivi", "OneDrive")

# Added "OneDrive" to shortcut targets to catch any stray .lnk files
$shortcutTargets = @("Send to OneNote Tool", "OneNote2010", "Microsoft Office OneNote Quick Launch", "Send to OneNote", "OneDrive")

$foundIssues = $false

# Check HKCU Registry only
$hkcuRunPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
foreach ($app in $registryTargets) {
    if (Get-ItemProperty -Path $hkcuRunPath -Name $app -ErrorAction SilentlyContinue) { 
        $foundIssues = $true 
    }
}

# Check User Startup Folder only
$userStartupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
foreach ($target in $shortcutTargets) {
    if (Get-ChildItem -Path $userStartupFolder -Filter "*$target*.lnk" -ErrorAction SilentlyContinue) { 
        $foundIssues = $true 
    }
}

if ($foundIssues) {
    Write-Host "Target startup items found in current user context. Remediation required."
    Exit 1
} else {
    Write-Host "Healthy. No target startup items found for current user."
    Exit 0
}