# Define the target registry paths and properties
$RegistryTargets = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{3936E9E4-D92C-4EEE-A85A-BC16D5EA0819}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{04731B67-D933-450a-90E6-4ACD2E9408FE}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{1CF1260C-4DD0-4ebb-811F-33C572699FDE}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}"; Name = "HiddenByDefault"; Expected = 1; ValueType = "DWord" }
)

$NonCompliantCount = 0

foreach ($Target in $RegistryTargets) {
    if (Test-Path $Target.Path) {
        $CurrentValue = Get-ItemProperty -Path $Target.Path -Name $Target.Name -ErrorAction SilentlyContinue
        if ($null -eq $CurrentValue -or $CurrentValue.$($Target.Name) -ne $Target.Expected) {
            Write-Host "Non-Compliant: $($Target.Path) has an incorrect or missing value."
            $NonCompliantCount++
        }
    } else {
        Write-Host "Non-Compliant: Path does not exist: $($Target.Path)"
        $NonCompliantCount++
    }
}

if ($NonCompliantCount -gt 0) {
    Write-Host "Device is non-compliant. $NonCompliantCount items need remediation."
    Exit 1
} else {
    Write-Host "Device is fully compliant."
    Exit 0
}