#Detect-WindowsUpdateHealthTools
if (Get-Service -Name "Microsoft Update Health Service") {
    Exit 0
} else {
    Exit 1
}
