# ========================================================
# Script: Auditoria de Tarefas Agendadas para Relatorio HTML
# ========================================================

$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\Relatorio_Tarefas_Agendadas.html"

function Encode-HtmlString([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

Write-Host "[+] Coletando tarefas agendadas..." -ForegroundColor Cyan
$AllTasks = Get-ScheduledTask -ErrorAction SilentlyContinue

# Regras de analise heuristica
$SuspiciousPathPatterns = @(
    '\\AppData\\',
    '\\Temp\\',
    '\\Users\\Public\\',
    '\\ProgramData\\(?!Microsoft\\)'
)

$SuspiciousExecutables = @(
    'powershell\.exe',
    'pwsh\.exe',
    'cmd\.exe',
    'wscript\.exe',
    'cscript\.exe',
    'mshta\.exe',
    'certutil\.exe',
    'rundll32\.exe',
    'regsvr32\.exe',
    'bitsadmin\.exe',
    'curl\.exe'
)

$SuspiciousArguments = @(
    '-enc',
    '-encodedcommand',
    'bypass',
    '-w hidden',
    '-windowstyle hidden',
    'downloadstring',
    'invoke-webrequest',
    'iex',
    'http://',
    'https://'
)

Write-Host "[+] Analisando vetores de persistencia..." -ForegroundColor Cyan
$ReportData = foreach ($task in $AllTasks) {
    $actions = $task.Actions | Where-Object { $_ -is [Microsoft.Management.Infrastructure.CimInstance] }
    
    $executables = ($actions | ForEach-Object { $_.Execute }) -join ' ; '
    $arguments   = ($actions | ForEach-Object { $_.Arguments }) -join ' ; '
    
    $isSuspicious = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    # 1. Caminhos gravaveis
    foreach ($pathPattern in $SuspiciousPathPatterns) {
        if ($executables -match $pathPattern -or $arguments -match $pathPattern) {
            $isSuspicious = $true
            $reasons.Add("Caminho em diretorio gravavel ($pathPattern)")
            break
        }
    }

    # 2. Binarios LotL
    foreach ($exe in $SuspiciousExecutables) {
        if ($executables -match "(?i)$exe") {
            $isSuspicious = $true
            $reasons.Add("Binario LotL detectado ($exe)")
            break
        }
    }

    # 3. Argumentos evasivos
    foreach ($arg in $SuspiciousArguments) {
        if ($arguments -match "(?i)$arg") {
            $isSuspicious = $true
            $reasons.Add("Argumento evasivo detectado ($arg)")
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($executables)) {
        $executables = "[N/A - Acao COM ou personalizada]"
    }

    [PSCustomObject]@{
        TaskName      = $task.TaskName
        TaskPath      = $task.TaskPath
        State         = $task.State.ToString()
        Author        = if ($task.Author) { $task.Author } else { "N/A" }
        ActionExecute = $executables
        ActionArgs    = if ($arguments) { $arguments } else { "-" }
        IsSuspicious  = $isSuspicious
        RiskReason    = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" }
    }
}

$TotalCount = $ReportData.Count
$SuspiciousCount = ($ReportData | Where-Object { $_.IsSuspicious }).Count

Write-Host "[+] Total de tarefas: $TotalCount | Potencialmente suspeitas: $SuspiciousCount" -ForegroundColor Yellow

# Construtor do HTML usando StringBuilder para evitar problemas de escape de aspas
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="pt-BR">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('    <meta charset="UTF-8">')
[void]$sb.AppendLine('    <title>Auditoria de Tarefas Agendadas</title>')
[void]$sb.AppendLine('    <style>')
[void]$sb.AppendLine('        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 24px; background: #0f172a; color: #f8fafc; }')
[void]$sb.AppendLine('        h1 { margin-bottom: 6px; font-weight: 600; }')
[void]$sb.AppendLine('        .summary-bar { display: flex; gap: 16px; margin: 20px 0; }')
[void]$sb.AppendLine('        .stat-card { background: #1e293b; padding: 14px 20px; border-radius: 8px; border: 1px solid #334155; min-width: 140px; }')
[void]$sb.AppendLine('        .stat-val { font-size: 24px; font-weight: bold; margin-top: 4px; }')
[void]$sb.AppendLine('        .stat-val.alert { color: #f87171; }')
[void]$sb.AppendLine('        .controls { display: flex; gap: 12px; margin-bottom: 16px; align-items: center; }')
[void]$sb.AppendLine('        input[type="text"] { flex-grow: 1; padding: 10px 14px; border-radius: 6px; border: 1px solid #475569; background: #1e293b; color: #fff; font-size: 14px; outline: none; }')
[void]$sb.AppendLine('        input[type="text"]:focus { border-color: #38bdf8; }')
[void]$sb.AppendLine('        .btn-filter { padding: 9px 16px; border-radius: 6px; border: 1px solid #475569; background: #1e293b; color: #cbd5e1; cursor: pointer; font-size: 13px; font-weight: 500; }')
[void]$sb.AppendLine('        .btn-filter.active { background: #38bdf8; color: #0f172a; border-color: #38bdf8; font-weight: 600; }')
[void]$sb.AppendLine('        table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 8px; overflow: hidden; font-size: 13px; border: 1px solid #334155; }')
[void]$sb.AppendLine('        th { background: #0f172a; text-align: left; padding: 12px 14px; color: #94a3b8; font-weight: 600; border-bottom: 1px solid #334155; white-space: nowrap; }')
[void]$sb.AppendLine('        td { padding: 10px 14px; border-bottom: 1px solid #334155; word-break: break-all; color: #cbd5e1; }')
[void]$sb.AppendLine('        tr:hover td { background: #243247; }')
[void]$sb.AppendLine('        tr.suspicious { background: rgba(239, 68, 68, 0.12); }')
[void]$sb.AppendLine('        tr.suspicious:hover td { background: rgba(239, 68, 68, 0.22); }')
[void]$sb.AppendLine('        .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; text-transform: uppercase; }')
[void]$sb.AppendLine('        .badge-alert { background: #ef4444; color: #fff; }')
[void]$sb.AppendLine('        .badge-safe { background: #22c55e; color: #052e16; }')
[void]$sb.AppendLine('        .path { font-family: Consolas, monospace; color: #38bdf8; }')
[void]$sb.AppendLine('        .code { font-family: Consolas, monospace; color: #f1f5f9; }')
[void]$sb.AppendLine('    </style>')
[void]$sb.AppendLine('</head>')
[void]$sb.AppendLine('<body>')
[void]$sb.AppendLine("    <h1>Relatório de Tarefas Agendadas</h1>")
[void]$sb.AppendLine("    <p style='color: #94a3b8; margin: 0;'>Host: <strong>$($env:COMPUTERNAME)</strong> | Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>")
[void]$sb.AppendLine('    <div class="summary-bar">')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">TOTAL DE TAREFAS</div>')
[void]$sb.AppendLine("            <div class='stat-val'>$TotalCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">POTENCIALMENTE SUSPEITAS</div>')
[void]$sb.AppendLine("            <div class='stat-val alert'>$SuspiciousCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <div class="controls">')
[void]$sb.AppendLine('        <input type="text" id="searchInput" onkeyup="filterTable()" placeholder="Buscar por tarefa, binario, pasta ou argumento...">')
[void]$sb.AppendLine('        <button class="btn-filter active" id="btnAll" onclick="setMode(''all'')">Todas</button>')
[void]$sb.AppendLine('        <button class="btn-filter" id="btnSuspicious" onclick="setMode(''suspicious'')">Apenas Suspeitas</button>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <table id="tasksTable">')
[void]$sb.AppendLine('        <thead>')
[void]$sb.AppendLine('            <tr>')
[void]$sb.AppendLine('                <th>Status</th>')
[void]$sb.AppendLine('                <th>Nome da Tarefa</th>')
[void]$sb.AppendLine('                <th>Caminho</th>')
[void]$sb.AppendLine('                <th>Executavel / Binario</th>')
[void]$sb.AppendLine('                <th>Argumentos</th>')
[void]$sb.AppendLine('                <th>Autor</th>')
[void]$sb.AppendLine('                <th>Diagnostico</th>')
[void]$sb.AppendLine('            </tr>')
[void]$sb.AppendLine('        </thead>')
[void]$sb.AppendLine('        <tbody>')

foreach ($row in $ReportData) {
    $rowClass = if ($row.IsSuspicious) { "suspicious" } else { "normal" }
    $badge = if ($row.IsSuspicious) {
        "<span class='badge badge-alert'>Alerta</span>"
    } else {
        "<span class='badge badge-safe'>OK</span>"
    }

    $tName = Encode-HtmlString $row.TaskName
    $tPath = Encode-HtmlString $row.TaskPath
    $tExec = Encode-HtmlString $row.ActionExecute
    $tArgs = Encode-HtmlString $row.ActionArgs
    $tAuth = Encode-HtmlString $row.Author
    $tRisk = Encode-HtmlString $row.RiskReason
    $isSusp = $row.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("            <tr class='$rowClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                <td>$badge</td>")
    [void]$sb.AppendLine("                <td><strong>$tName</strong></td>")
    [void]$sb.AppendLine("                <td class='path'>$tPath</td>")
    [void]$sb.AppendLine("                <td class='code'>$tExec</td>")
    [void]$sb.AppendLine("                <td class='code'>$tArgs</td>")
    [void]$sb.AppendLine("                <td>$tAuth</td>")
    [void]$sb.AppendLine("                <td>$tRisk</td>")
    [void]$sb.AppendLine("            </tr>")
}

[void]$sb.AppendLine('        </tbody>')
[void]$sb.AppendLine('    </table>')
[void]$sb.AppendLine('    <script>')
[void]$sb.AppendLine("        let currentMode = 'all';")
[void]$sb.AppendLine("        function setMode(mode) {")
[void]$sb.AppendLine("            currentMode = mode;")
[void]$sb.AppendLine("            document.getElementById('btnAll').classList.toggle('active', mode === 'all');")
[void]$sb.AppendLine("            document.getElementById('btnSuspicious').classList.toggle('active', mode === 'suspicious');")
[void]$sb.AppendLine("            filterTable();")
[void]$sb.AppendLine("        }")
[void]$sb.AppendLine("        function filterTable() {")
[void]$sb.AppendLine("            const query = document.getElementById('searchInput').value.toLowerCase();")
[void]$sb.AppendLine("            const rows = document.querySelectorAll('#tasksTable tbody tr');")
[void]$sb.AppendLine("            rows.forEach(row => {")
[void]$sb.AppendLine("                const text = row.innerText.toLowerCase();")
[void]$sb.AppendLine("                const isSuspicious = row.getAttribute('data-suspicious') === 'true';")
[void]$sb.AppendLine("                const matchesSearch = text.includes(query);")
[void]$sb.AppendLine("                const matchesMode = (currentMode === 'all') || (currentMode === 'suspicious' && isSuspicious);")
[void]$sb.AppendLine("                if (matchesSearch && matchesMode) { row.style.display = ''; } else { row.style.display = 'none'; }")
[void]$sb.AppendLine("            });")
[void]$sb.AppendLine("        }")
[void]$sb.AppendLine('    </script>')
[void]$sb.AppendLine('</body>')
[void]$sb.AppendLine('</html>')

# Salva em UTF-8 com BOM para garantir compatibilidade com qualquer versao do Windows/PowerShell
$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $utf8WithBom)

Write-Host "[OK] Relatorio gerado com sucesso: $OutputPath" -ForegroundColor Green
Invoke-Item $OutputPath
