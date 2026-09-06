$eventsToMonitor = @(
    @{ID=4624; Log="Security"; Description="Logon bem-sucedido"},
    @{ID=4625; Log="Security"; Description="Falha de logon"},
    @{ID=4648; Log="Security"; Description="Uso de credenciais explícitas"},
    @{ID=4688; Log="Security"; Description="Novo processo criado"},
    @{ID=4720; Log="Security"; Description="Conta de usuário criada"},
    @{ID=4732; Log="Security"; Description="Usuário adicionado a grupo privilegiado"},
    @{ID=4740; Log="Security"; Description="Conta bloqueada"},
    @{ID=1102; Log="Security"; Description="Log de auditoria apagado"},

    @{ID=7045; Log="System"; Description="Novo serviço instalado"},

    @{ID=1116; Log="Microsoft-Windows-Windows Defender/Operational"; Description="Malware detectado pelo Windows Defender"},
    @{ID=5001; Log="Microsoft-Windows-Windows Defender/Operational"; Description="Proteção em tempo real desabilitada"},

    @{ID=4103; Log="Microsoft-Windows-PowerShell/Operational"; Description="Módulo PowerShell executado"},
    @{ID=4104; Log="Microsoft-Windows-PowerShell/Operational"; Description="Script PowerShell executado"}
)

$lastHour = (Get-Date).AddHours(-1)

foreach ($eventInfo in $eventsToMonitor) {

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = $eventInfo.Log
        ID        = $eventInfo.ID
        StartTime = $lastHour
    } -ErrorAction SilentlyContinue

    if ($events) {

        $latest = $events | Sort-Object TimeCreated -Descending | Select-Object -First 1

        $subject = "ALERTA SIEM - Evento $($eventInfo.ID)"

        $body = @"
Evento detectado

ID: $($eventInfo.ID)
Descrição: $($eventInfo.Description)
Log: $($eventInfo.Log)
Quantidade: $($events.Count)

Host: $($latest.MachineName)
Data/Hora: $($latest.TimeCreated)

Mensagem:
$($latest.Message)
"@

        $file = "C:\Alertas\EventLog_Alerts.txt"

        $body | Out-File -FilePath $file -Encoding UTF8

        $hookurl = "https://discord.com/api/webhooks/1429592953692749976/JTeF7oOI01Khgvot3El_Y_EMQ9_WMY0uHZLPuKcEl5Y15PH44vTZIOerDXx9Oq5mkECL"

        if (Test-Path $file) {
            curl.exe -F "file1=@$file" $hookurl
        }
    }
}
