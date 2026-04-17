# Detection Script: Identify installed VS Code Extensions
$UserProfiles = Get-ChildItem "C:\Users" -Directory
$Results = @()

foreach ($Profile in $UserProfiles) {
    $ExtPath = Join-Path $Profile.FullName ".vscode\extensions"
    
    if (Test-Path $ExtPath) {
        $Extensions = Get-ChildItem $ExtPath -Directory | Select-Object -ExpandProperty Name
        if ($Extensions) {
            $Results += "User: $($Profile.Name) | Extensions: $($Extensions -join ', ')"
        }
    }
}

if ($Results.Count -gt 0) {
    # Non-compliant: Extensions were found. Output them for Intune reporting.
    Write-Output ($Results -join " || ")
    exit 1 
} else {
    # Compliant: No extensions found.
    Write-Output "No VS Code extensions detected."
    exit 0
}