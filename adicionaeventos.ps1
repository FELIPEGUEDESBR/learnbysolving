# ============================================================
# Criar tarefa agendada para monitoramento de eventos Windows
# ============================================================

# Caminho do seu script
$ScriptPath = "C:\Alertas\events.ps1"

# Nome da tarefa
$TaskName = "Monitoramento de Eventos de Segurança"

# Verifica se o script existe
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERRO: Script não encontrado:" -ForegroundColor Red
    Write-Host $ScriptPath
    exit 1
}

# PowerShell que será utilizado
$PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Argumentos
$Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Ação
$Action = New-ScheduledTaskAction `
    -Execute $PowerShellPath `
    -Argument $Arguments

# Executar como SYSTEM
$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Executar a cada 60 minutos
$Trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 60) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# Configurações da tarefa
$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

# Cria a tarefa
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force

Write-Host ""
Write-Host "Tarefa criada com sucesso!" -ForegroundColor Green
Write-Host "Nome: $TaskName"
Write-Host "Script: $ScriptPath"
Write-Host "Intervalo: 5 minutos"
Write-Host "Usuário: SYSTEM"
Write-Host "Privilégios: Máximos"
