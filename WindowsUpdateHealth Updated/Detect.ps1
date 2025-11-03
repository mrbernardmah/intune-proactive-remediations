$service = Get-Service -Name "uhssvc" -ErrorAction SilentlyContinue

if ($null -ne $service -and $service.Status -eq 'Running') {
    Write-Output "Microsoft Update Health Service is running."
    Exit 0
} else {
    Write-Output "Microsoft Update Health Service is not running or not installed."
    Exit 1
}