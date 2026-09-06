# Startup Items
Get-CimInstance -Class Win32_StartupCommand
# Startup Folder
Get-ChildItem -Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
#Services
Get-Service | Where-Object {$_.StartType -eq 'Automatic'}
#Drivers
Get-WmiObject Win32_SystemDriver | Where-Object {$_.StartMode -eq 'Auto'}
# Registry
Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'

# Scheduled Tasks
Get-ScheduledTask | Where-Object {$_.Settings.StartWhenAvailable -eq $true -and $_.State -ne "Disabled"}
