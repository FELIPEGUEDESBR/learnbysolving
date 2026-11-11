# Disable Wi-Fi Sense 
Write-Host "Disabling Wi-Fi Sense..." 
If (!(Test-Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting")) { 
    New-Item -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Force | Out-Null 
} 
Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 0 
Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 0 

# Disable Bing Search in Start Menu 
Write-Host "Disabling Bing Search in Start Menu..." 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0

# Disable Location Tracking 
Write-Host "Disabling Location Tracking..." 
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type DWord -Value 0 
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value 0

# Disable Feedback 
Write-Host "Disabling Feedback..." 
If (!(Test-Path "HKCU:\Software\Microsoft\Siuf\Rules")) { 
    New-Item -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Force | Out-Null 
} 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0

# Disable Advertising ID 
Write-Host "Disabling Advertising ID..." 
If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo")) { 
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" | Out-Null 
} 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Type DWord -Value 0 

# Disable Cortana 
Write-Host "Disabling Cortana..." 
If (!(Test-Path "HKCU:\Software\Microsoft\Personalization\Settings")) { 
    New-Item -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Force | Out-Null 
} 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Type DWord -Value 0 
If (!(Test-Path "HKCU:\Software\Microsoft\InputPersonalization")) { 
    New-Item -Path "HKCU:\Software\Microsoft\InputPersonalization" -Force | Out-Null 
} 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Type DWord -Value 1 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Type DWord -Value 1 
If (!(Test-Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore")) { 
    New-Item -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Force | Out-Null 
} 
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Type DWord -Value 0

# Disable Remote Assistance 
Write-Host "Disabling Remote Assistance..." 
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Type DWord -Value 0

# Disable OneDrive 
Write-Host "Disabling OneDrive..." 
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive")) { 
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" | Out-Null 
 } 
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Type DWord -Value 1 

# Uninstall default Microsoft applications 
Write-Host "Uninstalling default Microsoft applications..." 
Get-AppxPackage "Microsoft.3DBuilder" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.BingFinance" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.BingNews" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.BingSports" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.BingWeather" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.Getstarted" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.MicrosoftOfficeHub" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.MicrosoftSolitaireCollection" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.Office.OneNote" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.People" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.SkypeApp" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.Windows.Photos" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.WindowsAlarms" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.WindowsCamera" | Remove-AppxPackage 
Get-AppxPackage "microsoft.windowscommunicationsapps" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.WindowsMaps" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.WindowsPhone" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.WindowsSoundRecorder" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.XboxApp" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.ZuneMusic" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.ZuneVideo" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.AppConnector" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.ConnectivityStore" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.Office.Sway" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.Messaging" | Remove-AppxPackage 
Get-AppxPackage "Microsoft.CommsPhone" | Remove-AppxPackage 
Get-AppxPackage "9E2F88E3.Twitter" | Remove-AppxPackage 
Get-AppxPackage "king.com.CandyCrushSodaSaga" | Remove-AppxPackage
