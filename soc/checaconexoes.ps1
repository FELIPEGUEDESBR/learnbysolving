# ==============================================================================
# Script: Auditoria de Conexoes de Rede Ativas com Heuristica de Suspeita
# ==============================================================================

$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\Relatorio_Conexoes_Rede.html"

function Encode-HtmlString([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

Write-Host "[+] Mapeando tabela de processos..." -ForegroundColor Cyan
$ProcessMap = @{}
Get-CimInstance Win32_Process | ForEach-Object {
    $ProcessMap[$_.ProcessId] = @{
        Name        = $_.Name
        Path        = $_.ExecutablePath
        CommandLine = $_.CommandLine
    }
}

# Heuristica de portas suspeitas (C2, proxies, shells reversos, trojans comuns)
$SuspiciousPorts = @(4444, 5555, 1337, 31337, 8888, 9999, 6667, 7777, 8081, 9001, 1080)

# Binarios e shells que normalmente nao deveriam iniciar conexoes de saida/escuta arbitrarias
$SuspiciousBinaries = @(
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
    'curl\.exe',
    'nc\.exe',
    'ncat\.exe'
)

# Diretorios gravaveis por usuarios comuns
$SuspiciousPathPatterns = @(
    '\\AppData\\',
    '\\Temp\\',
    '\\Users\\Public\\',
    '\\ProgramData\\(?!Microsoft\\)'
)

Write-Host "[+] Coletando conexoes TCP e UDP ativas..." -ForegroundColor Cyan
$TcpConnections = Get-NetTCPConnection -ErrorAction SilentlyContinue
$UdpEndpoints   = Get-NetUDPEndpoint -ErrorAction SilentlyContinue

Write-Host "[+] Analisando riscos e correlacionando processos..." -ForegroundColor Cyan
$ReportData = [System.Collections.Generic.List[PSCustomObject]]::new()

# Processa conexoes TCP
foreach ($conn in $TcpConnections) {
    $proc = $ProcessMap[$conn.OwningProcess]
    $procName = if ($proc.Name) { $proc.Name } else { "PID: $($conn.OwningProcess)" }
    $procPath = if ($proc.Path) { $proc.Path } else { "[Caminho inacessivel ou processo finalizado]" }
    $cmdLine  = if ($proc.CommandLine) { $proc.CommandLine } else { "-" }

    $isSuspicious = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    # 1. Execucao a partir de diretorios gravaveis
    foreach ($pattern in $SuspiciousPathPatterns) {
        if ($procPath -match $pattern) {
            $isSuspicious = $true
            $reasons.Add("Executavel em pasta gravavel ($pattern)")
            break
        }
    }

    # 2. Binarios LOLBins estabelecendo rede
    foreach ($bin in $SuspiciousBinaries) {
        if ($procName -match "(?i)^$bin$") {
            $isSuspicious = $true
            $reasons.Add("Binario nativo/shell em rede ($bin)")
            break
        }
    }

    # 3. Portas remotas ou locais de alto risco
    if ($SuspiciousPorts -contains [int]$conn.RemotePort) {
        $isSuspicious = $true
        $reasons.Add("Porta remota tipica de C2/Proxy ($($conn.RemotePort))")
    }
    if ($SuspiciousPorts -contains [int]$conn.LocalPort -and $conn.State -eq 'Listen') {
        $isSuspicious = $true
        $reasons.Add("Porta local de escuta suspeita ($($conn.LocalPort))")
    }

    $ReportData.Add([PSCustomObject]@{
        Protocol      = "TCP"
        LocalAddress  = "$($conn.LocalAddress):$($conn.LocalPort)"
        RemoteAddress = if ($conn.RemoteAddress -ne "0.0.0.0" -and $conn.RemoteAddress -ne "::") { "$($conn.RemoteAddress):$($conn.RemotePort)" } else { "-" }
        State         = $conn.State.ToString()
        ProcessID     = $conn.OwningProcess
        ProcessName   = $procName
        ProcessPath   = $procPath
        CommandLine   = $cmdLine
        IsSuspicious  = $isSuspicious
        RiskReason    = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" }
    })
}

# Processa endpoints UDP
foreach ($udp in $UdpEndpoints) {
    $proc = $ProcessMap[$udp.OwningProcess]
    $procName = if ($proc.Name) { $proc.Name } else { "PID: $($udp.OwningProcess)" }
    $procPath = if ($proc.Path) { $proc.Path } else { "[Caminho inacessivel ou processo finalizado]" }
    $cmdLine  = if ($proc.CommandLine) { $proc.CommandLine } else { "-" }

    $isSuspicious = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    foreach ($pattern in $SuspiciousPathPatterns) {
        if ($procPath -match $pattern) {
            $isSuspicious = $true
            $reasons.Add("Executavel em pasta gravavel ($pattern)")
            break
        }
    }

    foreach ($bin in $SuspiciousBinaries) {
        if ($procName -match "(?i)^$bin$") {
            $isSuspicious = $true
            $reasons.Add("Binario nativo/shell em rede ($bin)")
            break
        }
    }

    if ($SuspiciousPorts -contains [int]$udp.LocalPort) {
        $isSuspicious = $true
        $reasons.Add("Porta UDP de escuta suspeita ($($udp.LocalPort))")
    }

    $ReportData.Add([PSCustomObject]@{
        Protocol      = "UDP"
        LocalAddress  = "$($udp.LocalAddress):$($udp.LocalPort)"
        RemoteAddress = "-"
        State         = "-"
        ProcessID     = $udp.OwningProcess
        ProcessName   = $procName
        ProcessPath   = $procPath
        CommandLine   = $cmdLine
        IsSuspicious  = $isSuspicious
        RiskReason    = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" }
    })
}

$TotalCount      = $ReportData.Count
$SuspiciousCount = ($ReportData | Where-Object { $_.IsSuspicious }).Count

Write-Host "[+] Conexoes capturadas: $TotalCount | Potencialmente suspeitas: $SuspiciousCount" -ForegroundColor Yellow

# Montagem do template HTML via StringBuilder (evita quebras de sintaxe e escape)
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="pt-BR">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('    <meta charset="UTF-8">')
[void]$sb.AppendLine('    <title>Auditoria de Conexoes de Rede</title>')
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
[void]$sb.AppendLine("    <h1>Relatório de Conexões de Rede Ativas</h1>")
[void]$sb.AppendLine("    <p style='color: #94a3b8; margin: 0;'>Host: <strong>$($env:COMPUTERNAME)</strong> | Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>")
[void]$sb.AppendLine('    <div class="summary-bar">')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">TOTAL DE CONEXÕES</div>')
[void]$sb.AppendLine("            <div class='stat-val'>$TotalCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">POTENCIALMENTE SUSPEITAS</div>')
[void]$sb.AppendLine("            <div class='stat-val alert'>$SuspiciousCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <div class="controls">')
[void]$sb.AppendLine('        <input type="text" id="searchInput" onkeyup="filterTable()" placeholder="Buscar por IP, porta, executavel, processo, caminho...">')
[void]$sb.AppendLine('        <button class="btn-filter active" id="btnAll" onclick="setMode(''all'')">Todas</button>')
[void]$sb.AppendLine('        <button class="btn-filter" id="btnSuspicious" onclick="setMode(''suspicious'')">Apenas Suspeitas</button>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <table id="connectionsTable">')
[void]$sb.AppendLine('        <thead>')
[void]$sb.AppendLine('            <tr>')
[void]$sb.AppendLine('                <th>Status</th>')
[void]$sb.AppendLine('                <th>Proto</th>')
[void]$sb.AppendLine('                <th>Endereço Local</th>')
[void]$sb.AppendLine('                <th>Endereço Remoto</th>')
[void]$sb.AppendLine('                <th>Estado</th>')
[void]$sb.AppendLine('                <th>PID</th>')
[void]$sb.AppendLine('                <th>Processo</th>')
[void]$sb.AppendLine('                <th>Caminho do Binário</th>')
[void]$sb.AppendLine('                <th>Linha de Comando</th>')
[void]$sb.AppendLine('                <th>Diagnóstico</th>')
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

    $tProto   = Encode-HtmlString $row.Protocol
    $tLocal   = Encode-HtmlString $row.LocalAddress
    $tRemote  = Encode-HtmlString $row.RemoteAddress
    $tState   = Encode-HtmlString $row.State
    $tPID     = Encode-HtmlString $row.ProcessID
    $tPName   = Encode-HtmlString $row.ProcessName
    $tPPath   = Encode-HtmlString $row.ProcessPath
    $tCmd     = Encode-HtmlString $row.CommandLine
    $tRisk    = Encode-HtmlString $row.RiskReason
    $isSusp   = $row.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("            <tr class='$rowClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                <td>$badge</td>")
    [void]$sb.AppendLine("                <td><strong>$tProto</strong></td>")
    [void]$sb.AppendLine("                <td class='code'>$tLocal</td>")
    [void]$sb.AppendLine("                <td class='code'>$tRemote</td>")
    [void]$sb.AppendLine("                <td>$tState</td>")
    [void]$sb.AppendLine("                <td>$tPID</td>")
    [void]$sb.AppendLine("                <td><strong>$tPName</strong></td>")
    [void]$sb.AppendLine("                <td class='path'>$tPPath</td>")
    [void]$sb.AppendLine("                <td class='code'>$tCmd</td>")
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
[void]$sb.AppendLine("            const rows = document.querySelectorAll('#connectionsTable tbody tr');")
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

# Salva em UTF-8 com BOM para garantir compatibilidade
$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $utf8WithBom)

Write-Host "[OK] Relatório gerado com sucesso: $OutputPath" -ForegroundColor Green
Invoke-Item $OutputPath
