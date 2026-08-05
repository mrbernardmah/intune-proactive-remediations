$ErrorActionPreference = "Stop"
$threshold = 1GB

function Get-FolderSize {
    param([string]$Path)
    
    if (Test-Path $Path) {
        try {
            $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum).Sum
            if ($null -eq $size) { return 0 }
            return $size
        }
        catch { return 0 }
    }
    return 0
}

try {
    $totalSize = 0
    
    # Windows Temp
    $totalSize += Get-FolderSize "$env:WINDIR\Temp"
    
    # User Temp folders
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $totalSize += Get-FolderSize "$($_.FullName)\AppData\Local\Temp"
    }
    
    # Recycle Bin
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.NameSpace(0xA).Items() | ForEach-Object {
            $totalSize += $_.ExtendedProperty("Size")
        }
    }
    catch { 
        # Silently continue if unable to access recycle bin
    }
    
    Write-Output "Cleanable space: $([math]::Round($totalSize / 1GB, 2)) GB"
    
    if ($totalSize -gt $threshold) {
        exit 1
    }
    exit 0
}
catch {
    Write-Error $_
    exit 2
}