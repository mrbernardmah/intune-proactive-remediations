$shortcuts = "Google Chrome.lnk", "Microsoft Edge.lnk"
$found = $false

# Check Public Desktop
foreach ($s in $shortcuts) {
    if (Test-Path "$env:PUBLIC\Desktop\$s") { $found = $true }
}

# Check Individual User Desktops
$profiles = Get-ChildItem "C:\Users" -Exclude "All Users", "Default", "Default User"
foreach ($p in $profiles) {
    foreach ($s in $shortcuts) {
        if (Test-Path "$($p.FullName)\Desktop\$s") { $found = $true }
    }
}

if ($found) { Write-Host "Shortcuts detected"; exit 1 } else { Write-Host "Clean"; exit 0 }