#requires -Version 5.1

<#
.SYNOPSIS
    Dashboard local de auditoria e detecção de eventos de segurança.

.DESCRIPTION
    Compatível com PowerShell 5.1 e PowerShell 7.

    Analisa:
      4624 - Logon bem-sucedido
      4625 - Falha de logon
      4648 - Uso de credenciais explícitas
      4720 - Conta criada
      4732 - Usuário adicionado a grupo
      4740 - Conta bloqueada
      1102 - Log de auditoria apagado
      7045 - Serviço instalado
      1116 - Malware detectado pelo Defender
      5001 - Proteção em tempo real desabilitada
      4104 - Script PowerShell registrado

    O evento 4625 recebe análise específica para detectar possíveis
    ataques de força bruta.

.NOTES
    Compatível com:
      - Windows PowerShell 5.1
      - PowerShell 7+
#>

# ============================================================
# VERIFICAÇÃO DE PRIVILÉGIOS
# ============================================================
# A leitura do log "Security" normalmente exige uma sessão
# elevada (Executar como Administrador). Sem elevação,
# Get-WinEvent falha e o erro é engolido pelo -ErrorAction
# SilentlyContinue mais abaixo, o que pode dar a falsa
# impressão de que "não há eventos".

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

$isElevated = $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isElevated) {
    Write-Warning "Este script nao esta sendo executado como Administrador."
    Write-Warning "A leitura do log 'Security' pode falhar silenciosamente sem elevacao."
    Write-Warning "Recomenda-se reexecutar em um PowerShell elevado (Executar como Administrador)."
    Write-Host ""
}

# ============================================================
# CONFIGURAÇÃO
# ============================================================

$startDate = (Get-Date).AddMonths(-3)
$endDate   = Get-Date

# Quantidade máxima de eventos detalhados por regra
$maxEventsPerRule = 50

# Janela utilizada na detecção de força bruta
$bruteForceWindowMinutes = 10

# Número mínimo de falhas dentro da janela
$bruteForceThreshold = 8

# ============================================================
# REGRAS
# ============================================================

$eventRules = @(
    @{
        ID          = 4624
        Log         = "Security"
        Name        = "Logon bem-sucedido"
        Category    = "Autenticação"
        Severity    = "Info"
        Enabled     = $true
        Description = "Logon realizado com sucesso."
    },

    @{
        ID          = 4625
        Log         = "Security"
        Name        = "Falha de logon"
        Category    = "Autenticação"
        Severity    = "Medium"
        Enabled     = $true
        Description = "Falha de autenticação. Avaliada também pela detecção de força bruta."
    },

    @{
        ID          = 4648
        Log         = "Security"
        Name        = "Credenciais explícitas"
        Category    = "Autenticação"
        Severity    = "Medium"
        Enabled     = $true
        Description = "Um processo tentou autenticar utilizando credenciais fornecidas explicitamente."
    },

    @{
        ID          = 4720
        Log         = "Security"
        Name         = "Conta de usuário criada"
        Category     = "Identidade"
        Severity     = "High"
        Enabled      = $true
        Description  = "Nova conta de usuário criada."
    },

    @{
        ID          = 4732
        Log         = "Security"
        Name         = "Usuário adicionado a grupo"
        Category     = "Privilégio"
        Severity     = "High"
        Enabled      = $true
        Description  = "Usuário adicionado a um grupo local."
    },

    @{
        ID          = 4740
        Log         = "Security"
        Name         = "Conta bloqueada"
        Category     = "Autenticação"
        Severity     = "Medium"
        Enabled      = $true
        Description  = "Conta de usuário bloqueada."
    },

    @{
        ID          = 1102
        Log         = "Security"
        Name         = "Log de auditoria apagado"
        Category     = "Defesa"
        Severity     = "Critical"
        Enabled      = $true
        Description  = "O log de auditoria de segurança foi limpo."
    },

    @{
        ID          = 7045
        Log         = "System"
        Name         = "Novo serviço instalado"
        Category     = "Persistência"
        Severity     = "High"
        Enabled      = $true
        Description  = "Novo serviço instalado no sistema."
    },

    @{
        ID          = 1116
        Log         = "Microsoft-Windows-Windows Defender/Operational"
        Name         = "Malware detectado"
        Category     = "Defender"
        Severity     = "Critical"
        Enabled      = $true
        Description  = "Windows Defender registrou uma detecção de malware."
    },

    @{
        ID          = 5001
        Log         = "Microsoft-Windows-Windows Defender/Operational"
        Name         = "Proteção em tempo real desabilitada"
        Category     = "Defesa"
        Severity     = "High"
        Enabled      = $true
        Description  = "A proteção em tempo real do Windows Defender foi desabilitada."
    },

    @{
        ID          = 4104
        Log         = "Microsoft-Windows-PowerShell/Operational"
        Name         = "PowerShell Script Block Logging"
        Category     = "PowerShell"
        Severity     = "Medium"
        Enabled      = $true
        Description  = "Script PowerShell registrado pelo Script Block Logging."
    }
)

# ============================================================
# ESTRUTURAS DE DADOS
# ============================================================

$allEvents = New-Object System.Collections.ArrayList
$alerts    = New-Object System.Collections.ArrayList

$ruleStatistics = @{}

foreach ($rule in $eventRules) {

    $ruleStatistics[$rule.ID] = @{
        Name  = $rule.Name
        Count = 0
    }
}

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

function Get-EventDataValue {
    param(
        [Parameter(Mandatory=$true)]
        $Event,

        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    try {
        $xml = [xml]$Event.ToXml()

        foreach ($data in $xml.Event.EventData.Data) {
            if ($data.Name -eq $Name) {
                return [string]$data.'#text'
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-SeverityRank {
    param(
        [string]$Severity
    )

    switch ($Severity) {
        "Info"     { return 1 }
        "Low"      { return 2 }
        "Medium"   { return 3 }
        "High"     { return 4 }
        "Critical" { return 5 }
        default    { return 0 }
    }
}

function Add-Alert {
    param(
        [int]$EventId,
        [string]$RuleName,
        [string]$Category,
        [string]$Severity,
        [datetime]$TimeCreated,
        [string]$Computer,
        [string]$User,
        [string]$IP,
        [string]$Description,
        [string]$Message
    )

    $obj = [PSCustomObject]@{
        EventId     = $EventId
        Rule        = $RuleName
        Category    = $Category
        Severity    = $Severity
        TimeCreated = $TimeCreated
        Computer    = $Computer
        User        = $User
        IP          = $IP
        Description = $Description
        Message     = $Message
    }

    [void]$alerts.Add($obj)
}

# ============================================================
# COLETA DOS EVENTOS
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   DASHBOARD DE AUDITORIA DE SEGURANCA" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Periodo:"
Write-Host "Inicio : $($startDate.ToString('dd/MM/yyyy HH:mm:ss'))"
Write-Host "Fim    : $($endDate.ToString('dd/MM/yyyy HH:mm:ss'))"
Write-Host ""

foreach ($rule in $eventRules) {

    if (-not $rule.Enabled) {
        continue
    }

    Write-Host "Analisando Event ID $($rule.ID) - $($rule.Name)..." -ForegroundColor Yellow

    try {

        # ====================================================
        # IMPORTANTE:
        # FilterHashtable executa a filtragem no próprio
        # mecanismo de Event Log, evitando trazer milhares
        # de eventos para o PowerShell.
        # ====================================================

        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = $rule.Log
            Id        = $rule.ID
            StartTime = $startDate
            EndTime   = $endDate
        } -ErrorAction SilentlyContinue)

        $count = $events.Count

        $ruleStatistics[$rule.ID].Count = $count

        Write-Host "  Encontrados: $count"

        if ($count -eq 0) {
            continue
        }

        # ----------------------------------------------------
        # Guarda somente uma amostra para o relatório
        # ----------------------------------------------------

        $sample = @(
            $events |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $maxEventsPerRule
        )

        foreach ($evt in $sample) {

            $user = $null
            $ip   = $null

            switch ($rule.ID) {

                4624 {
                    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
                    $ip   = Get-EventDataValue -Event $evt -Name "IpAddress"
                }

                4625 {
                    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
                    $ip   = Get-EventDataValue -Event $evt -Name "IpAddress"
                }

                4648 {
                    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
                }

                4720 {
                    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
                }

                4732 {
                    $user = Get-EventDataValue -Event $evt -Name "MemberName"
                }

                4740 {
                    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
                    $ip   = Get-EventDataValue -Event $evt -Name "CallerComputerName"
                }

                7045 {
                    $user = Get-EventDataValue -Event $evt -Name "AccountName"
                }
            }

            # ------------------------------------------------
            # Eventos que merecem aparecer diretamente
            # como alerta
            # ------------------------------------------------

            switch ($rule.ID) {

                4720 {
                    Add-Alert `
                        -EventId 4720 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity $rule.Severity `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }

                4732 {
                    Add-Alert `
                        -EventId 4732 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity $rule.Severity `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }

                1102 {
                    Add-Alert `
                        -EventId 1102 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity "Critical" `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }

                7045 {
                    Add-Alert `
                        -EventId 7045 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity $rule.Severity `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }

                1116 {
                    Add-Alert `
                        -EventId 1116 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity "Critical" `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }

                5001 {
                    Add-Alert `
                        -EventId 5001 `
                        -RuleName $rule.Name `
                        -Category $rule.Category `
                        -Severity "High" `
                        -TimeCreated $evt.TimeCreated `
                        -Computer $evt.MachineName `
                        -User $user `
                        -IP $ip `
                        -Description $rule.Description `
                        -Message $evt.Message
                }
            }
        }
    }
    catch {
        Write-Warning "Falha ao analisar ID $($rule.ID): $($_.Exception.Message)"
    }
}

# ============================================================
# DETECÇÃO DE FORÇA BRUTA - EVENT ID 4625
# ============================================================

Write-Host ""
Write-Host "Executando deteccao de possivel forca bruta..." -ForegroundColor Cyan

try {

    $failedLogons = @(
        Get-WinEvent -FilterHashtable @{
            LogName   = "Security"
            Id        = 4625
            StartTime = $startDate
            EndTime   = $endDate
        } -ErrorAction SilentlyContinue
    )

    # --------------------------------------------------------
    # O agrupamento é feito por IP + usuário.
    #
    # Isso é muito melhor que:
    #
    #     if ($events.Count -gt 10)
    #
    # porque 10 falhas distribuídas ao longo de 3 meses
    # não significam necessariamente força bruta.
    # --------------------------------------------------------

    $failedLogonObjects = foreach ($evt in $failedLogons) {

        $user = Get-EventDataValue -Event $evt -Name "TargetUserName"
        $ip   = Get-EventDataValue -Event $evt -Name "IpAddress"

        # Ignora alguns valores que não representam IP útil
        if ([string]::IsNullOrWhiteSpace($ip) -or
            $ip -eq "-" -or
            $ip -eq "::1" -or
            $ip -eq "127.0.0.1") {

            $ip = "LOCAL"
        }

        [PSCustomObject]@{
            TimeCreated = $evt.TimeCreated
            User        = $user
            IP          = $ip
            Computer    = $evt.MachineName
            Message     = $evt.Message
        }
    }

    # Agrupa por usuário e origem
    $groups = $failedLogonObjects |
        Group-Object User, IP

    foreach ($group in $groups) {

        $ordered = $group.Group |
            Sort-Object TimeCreated

        if ($ordered.Count -lt $bruteForceThreshold) {
            continue
        }

        # ----------------------------------------------------
        # Sliding window
        # ----------------------------------------------------

        for ($i = 0; $i -lt $ordered.Count; $i++) {

            $windowStart = $ordered[$i].TimeCreated
            $windowEnd   = $windowStart.AddMinutes($bruteForceWindowMinutes)

            $windowEvents = @(
                $ordered |
                Where-Object {
                    $_.TimeCreated -ge $windowStart -and
                    $_.TimeCreated -le $windowEnd
                }
            )

            if ($windowEvents.Count -ge $bruteForceThreshold) {

                $first = $windowEvents[0]

                $description = "Possível força bruta: $($windowEvents.Count) falhas de autenticação para '$($group.Name)' em aproximadamente $bruteForceWindowMinutes minutos."

                Add-Alert `
                    -EventId 4625 `
                    -RuleName "Possível ataque de força bruta" `
                    -Category "Autenticação" `
                    -Severity "High" `
                    -TimeCreated $first.TimeCreated `
                    -Computer $first.Computer `
                    -User $first.User `
                    -IP $first.IP `
                    -Description $description `
                    -Message (($windowEvents | ForEach-Object {
                        "$($_.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')) - $($_.Message)"
                    }) -join "`r`n")

                # Evita gerar vários alertas para a mesma sequência
                break
            }
        }
    }
}
catch {
    Write-Warning "Falha na análise de força bruta: $($_.Exception.Message)"
}

# ============================================================
# ANÁLISE DE 4648
# ============================================================

# 4648 isoladamente não significa ataque.
#
# Ele pode ocorrer legitimamente em:
#   - RunAs
#   - tarefas administrativas
#   - ferramentas de administração
#   - aplicações que utilizam credenciais explícitas
#
# Portanto, não o transformamos automaticamente em HIGH/CRITICAL.

# ============================================================
# ANÁLISE DE 4740
# ============================================================

# Um bloqueio isolado não é necessariamente ataque.
#
# Porém, como pode estar relacionado a password spraying/
# força bruta, ele permanece no relatório como MEDIUM.

foreach ($evt in @(
    Get-WinEvent -FilterHashtable @{
        LogName   = "Security"
        Id        = 4740
        StartTime = $startDate
        EndTime   = $endDate
    } -ErrorAction SilentlyContinue |
    Select-Object -First $maxEventsPerRule
)) {

    $user = Get-EventDataValue -Event $evt -Name "TargetUserName"

    Add-Alert `
        -EventId 4740 `
        -RuleName "Conta bloqueada" `
        -Category "Autenticação" `
        -Severity "Medium" `
        -TimeCreated $evt.TimeCreated `
        -Computer $evt.MachineName `
        -User $user `
        -IP "" `
        -Description "Conta bloqueada. Avaliar juntamente com eventos 4625 próximos no tempo." `
        -Message $evt.Message
}

# ============================================================
# ANÁLISE DO EVENTO 4104
# ============================================================

# Nem todo PowerShell Script Block é malicioso.
#
# Procuramos apenas indicadores básicos de comportamento
# potencialmente suspeito.
#
# Esta é uma heurística, não uma prova de comprometimento.

try {

    $psEvents = @(
        Get-WinEvent -FilterHashtable @{
            LogName   = "Microsoft-Windows-PowerShell/Operational"
            Id        = 4104
            StartTime = $startDate
            EndTime   = $endDate
        } -ErrorAction SilentlyContinue
    )

    $suspiciousPatterns = @(
        "Invoke-Mimikatz",
        "sekurlsa",
        "Get-Keystrokes",
        "DumpCreds",
        "FromBase64String",
        "EncodedCommand",
        "DownloadString",
        "Net.WebClient",
        "Invoke-WebRequest",
        "IEX",
        "Invoke-Expression",
        "Reflection.Assembly",
        "Add-MpPreference",
        "Set-MpPreference"
    )

    foreach ($evt in $psEvents) {

        $message = $evt.Message

        $matches = @(
            $suspiciousPatterns |
            Where-Object {
                $message -match [regex]::Escape($_)
            }
        )

        if ($matches.Count -gt 0) {

            Add-Alert `
                -EventId 4104 `
                -RuleName "PowerShell potencialmente suspeito" `
                -Category "PowerShell" `
                -Severity "High" `
                -TimeCreated $evt.TimeCreated `
                -Computer $evt.MachineName `
                -User "" `
                -IP "" `
                -Description ("Indicadores encontrados: " + ($matches -join ", ")) `
                -Message $message
        }
    }
}
catch {
    Write-Warning "Falha na análise do PowerShell 4104."
}

# ============================================================
# ORDENA ALERTAS
# ============================================================

$alerts = @(
    $alerts |
    Sort-Object `
        @{Expression={Get-SeverityRank $_.Severity};Descending=$true},
        @{Expression={$_.TimeCreated};Descending=$true}
)

# ============================================================
# ESTATÍSTICAS
# ============================================================

$totalAlerts = $alerts.Count

$critical = @($alerts | Where-Object Severity -eq "Critical").Count
$high     = @($alerts | Where-Object Severity -eq "High").Count
$medium   = @($alerts | Where-Object Severity -eq "Medium").Count
$low      = @($alerts | Where-Object Severity -eq "Low").Count
$info     = @($alerts | Where-Object Severity -eq "Info").Count

# Estatísticas por evento
$eventChartData = @(
    $ruleStatistics.GetEnumerator() |
    ForEach-Object {
        [PSCustomObject]@{
            Label = "$($_.Key) - $($_.Value.Name)"
            Count = $_.Value.Count
        }
    } |
    Where-Object Count -gt 0 |
    Sort-Object Count -Descending
)

# Estatísticas por severidade
$severityChartData = @(
    [PSCustomObject]@{Label="Critical";Count=$critical}
    [PSCustomObject]@{Label="High";Count=$high}
    [PSCustomObject]@{Label="Medium";Count=$medium}
    [PSCustomObject]@{Label="Low";Count=$low}
    [PSCustomObject]@{Label="Info";Count=$info}
) | Where-Object Count -gt 0

# ============================================================
# PREPARAÇÃO HTML
# ============================================================

$htmlRows = New-Object System.Collections.Generic.List[string]

foreach ($alert in $alerts) {

    $severityClass = $alert.Severity.ToLower()

    $row = @"
<tr
    data-severity="$([System.Net.WebUtility]::HtmlEncode($alert.Severity))"
    data-event="$($alert.EventId)"
    data-host="$([System.Net.WebUtility]::HtmlEncode($alert.Computer))"
>
    <td>
        <span class="event-id">
            ID $($alert.EventId)
        </span>
    </td>

    <td>
        <span class="severity $severityClass">
            $([System.Net.WebUtility]::HtmlEncode($alert.Severity))
        </span>
    </td>

    <td>
        <strong>$([System.Net.WebUtility]::HtmlEncode($alert.Rule))</strong>
        <br>
        <small>$([System.Net.WebUtility]::HtmlEncode($alert.Category))</small>
    </td>

    <td>
        $($alert.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))
    </td>

    <td>
        $([System.Net.WebUtility]::HtmlEncode($alert.Computer))
    </td>

    <td>
        $([System.Net.WebUtility]::HtmlEncode($alert.User))
    </td>

    <td>
        $([System.Net.WebUtility]::HtmlEncode($alert.IP))
    </td>

    <td>
        <details>
            <summary>Detalhes</summary>

            <div class="description">
                $([System.Net.WebUtility]::HtmlEncode($alert.Description))
            </div>

            <pre>$([System.Net.WebUtility]::HtmlEncode($alert.Message))</pre>
        </details>
    </td>
</tr>
"@

    $htmlRows.Add($row)
}

# ============================================================
# JSON PARA OS GRÁFICOS
# ============================================================

$eventChartJson = $eventChartData | ConvertTo-Json -Compress
$severityChartJson = $severityChartData | ConvertTo-Json -Compress

if ([string]::IsNullOrWhiteSpace($eventChartJson)) {
    $eventChartJson = "[]"
}

if ([string]::IsNullOrWhiteSpace($severityChartJson)) {
    $severityChartJson = "[]"
}

# ============================================================
# OPÇÕES DE FILTRO DE EVENTOS (gerado antes do here-string)
# ============================================================

$eventFilterOptions = ($eventRules | ForEach-Object {
    "<option value=""$($_.ID)"">ID $($_.ID) - $($_.Name)</option>"
}) -join "`n"

# ============================================================
# CAMINHO DO RELATÓRIO
# ============================================================

if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $reportPath = Join-Path (Get-Location) "Relatorio_Auditoria_Dashboard.html"
}
else {
    $reportPath = Join-Path $PSScriptRoot "Relatorio_Auditoria_Dashboard.html"
}

# ============================================================
# DASHBOARD HTML
# ============================================================

$html = @"
<!DOCTYPE html>

<html lang="pt-BR">

<head>

<meta charset="UTF-8">

<meta name="viewport"
      content="width=device-width, initial-scale=1.0">

<title>Dashboard de Segurança</title>

<style>

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 30px;
    font-family:
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        Arial,
        sans-serif;

    background: #f1f5f9;
    color: #0f172a;
}

.container {
    max-width: 1800px;
    margin: auto;
}

.header {
    background: white;
    border-radius: 14px;
    padding: 25px;
    margin-bottom: 20px;

    box-shadow:
        0 2px 10px rgba(0,0,0,.05);
}

.header h1 {
    margin: 0 0 8px 0;
}

.header p {
    margin: 0;
    color: #64748b;
}

.cards {
    display: grid;

    grid-template-columns:
        repeat(auto-fit, minmax(180px, 1fr));

    gap: 15px;

    margin-bottom: 20px;
}

.card {
    background: white;
    padding: 20px;
    border-radius: 12px;

    box-shadow:
        0 2px 10px rgba(0,0,0,.05);
}

.card-title {
    font-size: 13px;
    color: #64748b;
    text-transform: uppercase;
}

.card-value {
    font-size: 32px;
    font-weight: 700;
    margin-top: 5px;
}

.critical {
    color: #991b1b;
}

.high {
    color: #c2410c;
}

.medium {
    color: #b45309;
}

.low {
    color: #2563eb;
}

.info {
    color: #475569;
}

.dashboard {
    display: grid;

    grid-template-columns:
        repeat(auto-fit, minmax(400px, 1fr));

    gap: 20px;

    margin-bottom: 20px;
}

.panel {
    background: white;
    border-radius: 12px;
    padding: 20px;

    box-shadow:
        0 2px 10px rgba(0,0,0,.05);
}

.panel h2 {
    margin-top: 0;
    font-size: 17px;
}

.bar {
    display: flex;
    align-items: center;
    margin: 9px 0;
}

.bar-label {
    width: 210px;
    font-size: 12px;
}

.bar-container {
    flex: 1;
    height: 18px;
    background: #e2e8f0;
    border-radius: 5px;
    overflow: hidden;
}

.bar-fill {
    height: 100%;
    width: 0;
    background: #2563eb;
}

.bar-value {
    width: 60px;
    text-align: right;
    font-size: 12px;
    font-weight: bold;
}

.filters {
    display: grid;

    grid-template-columns:
        repeat(auto-fit, minmax(180px, 1fr));

    gap: 10px;

    margin-bottom: 20px;
}

input,
select {
    width: 100%;
    padding: 10px;

    border: 1px solid #cbd5e1;
    border-radius: 7px;

    background: white;
}

.table-wrapper {
    background: white;
    border-radius: 12px;
    overflow: auto;

    box-shadow:
        0 2px 10px rgba(0,0,0,.05);
}

table {
    width: 100%;
    border-collapse: collapse;
    min-width: 1300px;
}

th {
    background: #0f172a;
    color: white;

    padding: 12px;

    text-align: left;

    font-size: 12px;
}

td {
    padding: 12px;

    border-bottom:
        1px solid #e2e8f0;

    font-size: 13px;

    vertical-align: top;
}

tr:hover {
    background: #f8fafc;
}

.event-id {
    font-weight: bold;
    color: #334155;
}

.severity {
    display: inline-block;

    padding: 4px 8px;

    border-radius: 5px;

    font-size: 11px;

    font-weight: bold;
}

.severity.critical {
    background: #fee2e2;
    color: #991b1b;
}

.severity.high {
    background: #ffedd5;
    color: #c2410c;
}

.severity.medium {
    background: #fef3c7;
    color: #92400e;
}

.severity.low {
    background: #dbeafe;
    color: #1d4ed8;
}

.severity.info {
    background: #e2e8f0;
    color: #475569;
}

details {
    cursor: pointer;
}

summary {
    color: #2563eb;
    font-weight: 600;
}

pre {
    background: #0f172a;
    color: #cbd5e1;

    padding: 15px;

    border-radius: 7px;

    max-height: 350px;

    overflow: auto;

    white-space: pre-wrap;

    word-break: break-word;

    font-family:
        Consolas,
        "Courier New",
        monospace;

    font-size: 11px;
}

.description {
    margin: 10px 0;

    padding: 10px;

    background: #f8fafc;

    border-left: 3px solid #2563eb;
}

.footer {
    margin-top: 20px;

    color: #64748b;

    font-size: 12px;

    text-align: center;
}

.no-results {
    display: none;

    padding: 30px;

    text-align: center;

    color: #64748b;
}

</style>

</head>

<body>

<div class="container">

<div class="header">

<h1>Dashboard de Auditoria de Segurança</h1>

<p>
Período:
<strong>
$($startDate.ToString('dd/MM/yyyy HH:mm'))
</strong>
até
<strong>
$($endDate.ToString('dd/MM/yyyy HH:mm'))
</strong>
</p>

</div>

<!-- ================================================= -->
<!-- CARDS -->
<!-- ================================================= -->

<div class="cards">

<div class="card">
<div class="card-title">Total de alertas</div>
<div class="card-value">$totalAlerts</div>
</div>

<div class="card">
<div class="card-title">Críticos</div>
<div class="card-value critical">$critical</div>
</div>

<div class="card">
<div class="card-title">Alto risco</div>
<div class="card-value high">$high</div>
</div>

<div class="card">
<div class="card-title">Médio risco</div>
<div class="card-value medium">$medium</div>
</div>

<div class="card">
<div class="card-title">Baixo risco</div>
<div class="card-value low">$low</div>
</div>

<div class="card">
<div class="card-title">Informativos</div>
<div class="card-value info">$info</div>
</div>

</div>

<!-- ================================================= -->
<!-- GRÁFICOS -->
<!-- ================================================= -->

<div class="dashboard">

<div class="panel">

<h2>Distribuição por severidade</h2>

<div id="severityChart"></div>

</div>

<div class="panel">

<h2>Eventos encontrados</h2>

<div id="eventChart"></div>

</div>

</div>

<!-- ================================================= -->
<!-- FILTROS -->
<!-- ================================================= -->

<div class="panel">

<h2>Filtros</h2>

<div class="filters">

<select id="severityFilter">

<option value="">Todas as severidades</option>

<option value="Critical">Critical</option>
<option value="High">High</option>
<option value="Medium">Medium</option>
<option value="Low">Low</option>
<option value="Info">Info</option>

</select>

<select id="eventFilter">

<option value="">Todos os eventos</option>

$eventFilterOptions

</select>

<input
    id="hostFilter"
    type="text"
    placeholder="Filtrar por host..."
>

<input
    id="textFilter"
    type="text"
    placeholder="Pesquisar..."
>

</div>

</div>

<br>

<!-- ================================================= -->
<!-- TABELA -->
<!-- ================================================= -->

<div class="table-wrapper">

<table id="alertsTable">

<thead>

<tr>

<th>Evento</th>
<th>Severidade</th>
<th>Regra</th>
<th>Data/Hora</th>
<th>Host</th>
<th>Usuário</th>
<th>Origem</th>
<th>Detalhes</th>

</tr>

</thead>

<tbody>

$($htmlRows -join "`n")

</tbody>

</table>

<div id="noResults" class="no-results">

Nenhum evento corresponde aos filtros selecionados.

</div>

</div>

<div class="footer">

Dashboard gerado automaticamente pelo PowerShell.

</div>

</div>

<script>

var severityData = $severityChartJson;

var eventData = $eventChartJson;


/* ======================================================
   GRÁFICO DE BARRAS
   ====================================================== */

function createBars(elementId, data) {

    var container =
        document.getElementById(elementId);

    container.innerHTML = "";

    if (!data || data.length === 0) {

        container.innerHTML =
            "<p>Nenhum dado disponível.</p>";

        return;
    }

    var max = 0;

    data.forEach(function(item) {

        if (item.Count > max) {
            max = item.Count;
        }

    });

    data.forEach(function(item) {

        var row =
            document.createElement("div");

        row.className = "bar";

        var label =
            document.createElement("div");

        label.className = "bar-label";

        label.textContent = item.Label;

        var containerBar =
            document.createElement("div");

        containerBar.className =
            "bar-container";

        var fill =
            document.createElement("div");

        fill.className = "bar-fill";

        fill.style.width =
            ((item.Count / max) * 100) + "%";

        containerBar.appendChild(fill);

        var value =
            document.createElement("div");

        value.className = "bar-value";

        value.textContent = item.Count;

        row.appendChild(label);

        row.appendChild(containerBar);

        row.appendChild(value);

        container.appendChild(row);

    });
}


/* ======================================================
   FILTROS
   ====================================================== */

function applyFilters() {

    var severity =
        document.getElementById(
            "severityFilter"
        ).value;

    var eventId =
        document.getElementById(
            "eventFilter"
        ).value;

    var host =
        document.getElementById(
            "hostFilter"
        ).value.toLowerCase();

    var text =
        document.getElementById(
            "textFilter"
        ).value.toLowerCase();

    var rows =
        document.querySelectorAll(
            "#alertsTable tbody tr"
        );

    var visible = 0;

    rows.forEach(function(row) {

        var matchSeverity =
            !severity ||
            row.dataset.severity === severity;

        var matchEvent =
            !eventId ||
            row.dataset.event === eventId;

        var matchHost =
            !host ||
            row.dataset.host
                .toLowerCase()
                .indexOf(host) >= 0;

        var matchText =
            !text ||
            row.innerText
                .toLowerCase()
                .indexOf(text) >= 0;

        var visibleRow =
            matchSeverity &&
            matchEvent &&
            matchHost &&
            matchText;

        row.style.display =
            visibleRow ? "" : "none";

        if (visibleRow) {
            visible++;
        }

    });

    document.getElementById(
        "noResults"
    ).style.display =
        visible === 0 ? "block" : "none";
}


/* ======================================================
   EVENTOS
   ====================================================== */

document
    .getElementById("severityFilter")
    .addEventListener(
        "change",
        applyFilters
    );

document
    .getElementById("eventFilter")
    .addEventListener(
        "change",
        applyFilters
    );

document
    .getElementById("hostFilter")
    .addEventListener(
        "input",
        applyFilters
    );

document
    .getElementById("textFilter")
    .addEventListener(
        "input",
        applyFilters
    );


/* ======================================================
   INICIALIZAÇÃO
   ====================================================== */

createBars(
    "severityChart",
    severityData
);

createBars(
    "eventChart",
    eventData
);

</script>

</body>

</html>
"@

# ============================================================
# GRAVAÇÃO
# ============================================================

$html |
    Out-File `
        -FilePath $reportPath `
        -Encoding UTF8

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "Dashboard gerado com sucesso!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivo:"
Write-Host $reportPath -ForegroundColor Cyan
Write-Host ""
Write-Host "Alertas encontrados: $totalAlerts"
Write-Host "Critical: $critical"
Write-Host "High    : $high"
Write-Host "Medium  : $medium"
Write-Host "Low     : $low"
Write-Host "Info    : $info"
Write-Host ""

# Abre no navegador padrão
try {
    Start-Process $reportPath
}
catch {
    Invoke-Item $reportPath
}
