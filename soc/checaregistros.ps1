# ==============================================================================
# Script: Auditoria de Persistência no Registro do Windows (ASEPs)
# ==============================================================================

$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\Relatorio_Registro_Persistencia.html"

function Encode-HtmlString([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

Write-Host "[+] Definindo chaves críticas do Registro..." -ForegroundColor Cyan

# Coleção de locais estratégicos de persistência (HKLM e HKCU)
$RegistryTargets = @(
    # 1. Chaves de Inicialização Padrão (Run / RunOnce)
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows\CurrentVersion\Run"; Category = "Auto-Start (HKLM Run)" },
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows\CurrentVersion\RunOnce"; Category = "Auto-Start (HKLM RunOnce)" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows\CurrentVersion\Run"; Category = "Auto-Start (HKCU Run)" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows\CurrentVersion\RunOnce"; Category = "Auto-Start (HKCU RunOnce)" },
    @{ Hive = "LocalMachine"; Path = "Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Category = "Auto-Start (HKLM WoW64 Run)" },
    @{ Hive = "LocalMachine"; Path = "Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"; Category = "Auto-Start (HKLM WoW64 RunOnce)" },

    # 2. Sessão de Logon / Shell / Sub-sistemas
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Winlogon"; Category = "Logon Hijacking (Winlogon)" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows NT\CurrentVersion\Winlogon"; Category = "Logon Hijacking (Winlogon User)" },

    # 3. Hijacking de Execução de Imagem (IFEO - Debuggers e SilentProcessExit)
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"; Category = "IFEO Hijacking"; SubkeysOnly = $true },

    # 4. Injeções de DLL / Provedores LSA / DLLs de Inicialização
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Windows"; Category = "AppInit DLLs" },
    @{ Hive = "LocalMachine"; Path = "System\CurrentControlSet\Control\Lsa"; Category = "LSA Security Packages / Providers" },

    # 5. Políticas de Inicialização de Sistema e Explorer
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Category = "Policy Run (HKLM)" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Category = "Policy Run (HKCU)" }
)

# Heurísticas de detecção
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

Write-Host "[+] Inspecionando entradas do Registro..." -ForegroundColor Cyan
$ReportData = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($target in $RegistryTargets) {
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$($target.Hive), [Microsoft.Win32.RegistryView]::Registry64)
        $regKey  = $baseKey.OpenSubKey($target.Path)

        if (-not $regKey) { continue }

        # Caso especial para IFEO (varre subchaves em busca de 'Debugger')
        if ($target.SubkeysOnly) {
            foreach ($subName in $regKey.GetSubKeyNames()) {
                $subKey = $regKey.OpenSubKey($subName)
                if ($subKey) {
                    $valNames = $subKey.GetValueNames()
                    if ($valNames -contains "Debugger") {
                        $valData = [string]$subKey.GetValue("Debugger")
                        
                        $isSuspicious = $true
                        $reasons = [System.Collections.Generic.List[string]]::new()
                        $reasons.Add("IFEO 'Debugger' configurado para binário ($subName)")

                        $ReportData.Add([PSCustomObject]@{
                            Category     = $target.Category
                            RegistryPath = "$($target.Hive)\$($target.Path)\$subName"
                            ValueName    = "Debugger"
                            ValueData    = $valData
                            IsSuspicious = $isSuspicious
                            RiskReason   = $reasons -join " | "
                        })
                    }
                    $subKey.Close()
                }
            }
        }
        else {
            foreach ($valName in $regKey.GetValueNames()) {
                $valData = [string]$regKey.GetValue($valName)
                
                if ([string]::IsNullOrWhiteSpace($valData)) { continue }

                $isSuspicious = $false
                $reasons = [System.Collections.Generic.List[string]]::new()

                # 1. Checagem de AppInit_DLLs
                if ($valName -eq "AppInit_DLLs" -and $valData.Trim() -ne "") {
                    $isSuspicious = $true
                    $reasons.Add("AppInit_DLLs carregada no espaço de endereço de novos processos")
                }

                # 2. Checagem de Userinit / Shell alterados no Winlogon
                if ($target.Category -like "*Winlogon*") {
                    if ($valName -eq "Shell" -and $valData -notmatch '(?i)^explorer\.exe$') {
                        $isSuspicious = $true
                        $reasons.Add("Shell do Winlogon alterado (Padrão: explorer.exe)")
                    }
                    if ($valName -eq "Userinit" -and $valData -notmatch '(?i)^.*system32\\userinit\.exe,') {
                        $isSuspicious = $true
                        $reasons.Add("Userinit do Winlogon alterado (Padrão: userinit.exe)")
                    }
                }

                # 3. Caminhos em pastas graváveis
                foreach ($pattern in $SuspiciousPathPatterns) {
                    if ($valData -match $pattern) {
                        $isSuspicious = $true
                        $reasons.Add("Referência a pasta gravável ($pattern)")
                        break
                    }
                }

                # 4. Binários Living-off-the-Land (LotL)
                foreach ($exe in $SuspiciousExecutables) {
                    if ($valData -match "(?i)$exe") {
                        $isSuspicious = $true
                        $reasons.Add("Binário LotL detectado ($exe)")
                        break
                    }
                }

                # 5. Argumentos de evasão / download
                foreach ($arg in $SuspiciousArguments) {
                    if ($valData -match "(?i)$arg") {
                        $isSuspicious = $true
                        $reasons.Add("Argumento evasivo detectado ($arg)")
                        break
                    }
                }

                $ReportData.Add([PSCustomObject]@{
                    Category     = $target.Category
                    RegistryPath = "$($target.Hive)\$($target.Path)"
                    ValueName    = if ($valName -eq "") { "(Padrão)" } else { $valName }
                    ValueData    = $valData
                    IsSuspicious = $isSuspicious
                    RiskReason   = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" }
                })
            }
        }

        $regKey.Close()
        $baseKey.Close()
    }
    catch {
        # Acesso negado a chaves protegidas é esperado se não executado como Administrador
    }
}

$TotalCount = $ReportData.Count
$SuspiciousCount = ($ReportData | Where-Object { $_.IsSuspicious }).Count

Write-Host "[+] Total de entradas coletadas: $TotalCount | Potencialmente suspeitas: $SuspiciousCount" -ForegroundColor Yellow

# Construtor do HTML com StringBuilder
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="pt-BR">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('    <meta charset="UTF-8">')
[void]$sb.AppendLine('    <title>Auditoria de Persistência no Registro</title>')
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
[void]$sb.AppendLine("    <h1>Relatório de Persistência no Registro do Windows</h1>")
[void]$sb.AppendLine("    <p style='color: #94a3b8; margin: 0;'>Host: <strong>$($env:COMPUTERNAME)</strong> | Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>")
[void]$sb.AppendLine('    <div class="summary-bar">')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">TOTAL DE ENTRADAS</div>')
[void]$sb.AppendLine("            <div class='stat-val'>$TotalCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <div class="stat-card">')
[void]$sb.AppendLine('            <div style="color: #94a3b8; font-size: 12px;">POTENCIALMENTE SUSPEITAS</div>')
[void]$sb.AppendLine("            <div class='stat-val alert'>$SuspiciousCount</div>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <div class="controls">')
[void]$sb.AppendLine('        <input type="text" id="searchInput" onkeyup="filterTable()" placeholder="Buscar por chave, valor, executável, caminho ou diagnóstico...">')
[void]$sb.AppendLine('        <button class="btn-filter active" id="btnAll" onclick="setMode(''all'')">Todas</button>')
[void]$sb.AppendLine('        <button class="btn-filter" id="btnSuspicious" onclick="setMode(''suspicious'')">Apenas Suspeitas</button>')
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <table id="regTable">')
[void]$sb.AppendLine('        <thead>')
[void]$sb.AppendLine('            <tr>')
[void]$sb.AppendLine('                <th>Status</th>')
[void]$sb.AppendLine('                <th>Categoria</th>')
[void]$sb.AppendLine('                <th>Caminho do Registro</th>')
[void]$sb.AppendLine('                <th>Nome do Valor</th>')
[void]$sb.AppendLine('                <th>Dados / Comando</th>')
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

    $tCat   = Encode-HtmlString $row.Category
    $tPath  = Encode-HtmlString $row.RegistryPath
    $tName  = Encode-HtmlString $row.ValueName
    $tData  = Encode-HtmlString $row.ValueData
    $tRisk  = Encode-HtmlString $row.RiskReason
    $isSusp = $row.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("            <tr class='$rowClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                <td>$badge</td>")
    [void]$sb.AppendLine("                <td>$tCat</td>")
    [void]$sb.AppendLine("                <td class='path'>$tPath</td>")
    [void]$sb.AppendLine("                <td><strong>$tName</strong></td>")
    [void]$sb.AppendLine("                <td class='code'>$tData</td>")
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
[void]$sb.AppendLine("            const rows = document.querySelectorAll('#regTable tbody tr');")
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

# Escrita em UTF-8 com BOM para prevenir caracteres corrompidos
$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $utf8WithBom)

Write-Host "[OK] Relatório gerado com sucesso: $OutputPath" -ForegroundColor Green
Invoke-Item $OutputPath
