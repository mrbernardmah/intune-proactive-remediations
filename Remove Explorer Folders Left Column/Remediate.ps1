# Define the target registry paths, their default strings, and values
$RegistryTargets = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{3936E9E4-D92C-4EEE-A85A-BC16D5EA0819}"; DefaultValue = "CLSID_FrequentPlacesFolder" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}"; DefaultValue = "Removable Drives" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{04731B67-D933-450a-90E6-4ACD2E9408FE}"; DefaultValue = "CLSID_SearchFolder" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{1CF1260C-4DD0-4ebb-811F-33C572699FDE}"; DefaultValue = "CLSID_ThisPCMyMusicRegFolder" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}"; DefaultValue = "Computers and Devices" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"; DefaultValue = "CLSID_ThisPCDesktopRegFolder" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}"; DefaultValue = "CLSID_MSGraphHomeFolder" }
)

foreach ($Target in $RegistryTargets) {
    # Ensure the registry key path exists
    if (-not (Test-Path $Target.Path)) {
        New-Item -Path $Target.Path -Force | Out-Null
        Write-Host "Created missing registry path: $($Target.Path)"
    }

    # Set the (Default) string value for the key
    New-ItemProperty -Path $Target.Path -Name "(default)" -Value $Target.DefaultValue -PropertyType String -Force | Out-Null

    # Enforce the HiddenByDefault DWORD
    New-ItemProperty -Path $Target.Path -Name "HiddenByDefault" -Value 1 -PropertyType DWord -Force | Out-Null
    
    Write-Host "Successfully configured: $($Target.Path)"
}

Write-Host "Remediation complete. Restarting Explorer may be required for changes to take visual effect."