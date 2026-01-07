Get-NetConnectionProfile | Where-Object { $_.IPv4Connectivity -ne 'Disconnected' } |
Set-NetConnectionProfile -NetworkCategory Private