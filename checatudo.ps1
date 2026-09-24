#requires -Version 5.1

[CmdletBinding()]
param()

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    Write-Warning "[!] Script nao executado como Administrador."
    Write-Warning "    A leitura de logs 'Security' e chaves protegidas de 'HKLM' pode ser parcial."
    Write-Warning "    Recomenda-se executar em terminal elevado para auditoria completa."
    Write-Host ""
}

function Get-EventDataValue {
    param(
        [Parameter(Mandatory=$true)]$Event,
        [Parameter(Mandatory=$true)][string]$Name
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

function Get-SeverityRank([string]$Severity) {
    switch ($Severity) {
        "Info"     { return 1 }
        "Low"      { return 2 }
        "Medium"   { return 3 }
        "High"     { return 4 }
        "Critical" { return 5 }
        default    { return 0 }
    }
}

$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\Dashboard_Seguranca_Unificado.html"

$SuspiciousPathPatterns = @(
    '\\AppData\\',
    '\\Temp\\',
    '\\Users\\Public\\',
    '\\ProgramData\\(?!Microsoft\\)'
)

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

Write-Host "[1/4] Coletando e analisando Logs de Eventos..." -ForegroundColor Cyan

$startDate = (Get-Date).AddMonths(-3)
$endDate   = Get-Date
$maxEventsPerRule = 50
$bruteForceWindowMinutes = 10
$bruteForceThreshold = 8

$eventRules = @(
    @{ ID = 4624; Log = "Security"; Name = "Logon bem-sucedido"; Category = "Autenticacao"; Severity = "Info"; Enabled = $true; Description = "Logon realizado com sucesso." },
    @{ ID = 4625; Log = "Security"; Name = "Falha de logon"; Category = "Autenticacao"; Severity = "Medium"; Enabled = $true; Description = "Falha de autenticacao." },
    @{ ID = 4648; Log = "Security"; Name = "Credenciais explicitas"; Category = "Autenticacao"; Severity = "Medium"; Enabled = $true; Description = "Uso de credenciais explicitas." },
    @{ ID = 4720; Log = "Security"; Name = "Conta de usuario criada"; Category = "Identidade"; Severity = "High"; Enabled = $true; Description = "Nova conta criada." },
    @{ ID = 4732; Log = "Security"; Name = "Usuario adicionado a grupo"; Category = "Privilegio"; Severity = "High"; Enabled = $true; Description = "Membro adicionado a grupo local." },
    @{ ID = 4740; Log = "Security"; Name = "Conta bloqueada"; Category = "Autenticacao"; Severity = "Medium"; Enabled = $true; Description = "Conta bloqueada." },
    @{ ID = 1102; Log = "Security"; Name = "Log de auditoria apagado"; Category = "Defesa"; Severity = "Critical"; Enabled = $true; Description = "O log de seguranca foi limpo." },
    @{ ID = 7045; Log = "System"; Name = "Novo servico instalado"; Category = "Persistencia"; Severity = "High"; Enabled = $true; Description = "Novo servico registrado." },
    @{ ID = 1116; Log = "Microsoft-Windows-Windows Defender/Operational"; Name = "Malware detectado"; Category = "Defender"; Severity = "Critical"; Enabled = $true; Description = "Deteccao de ameaca pelo Defender." },
    @{ ID = 5001; Log = "Microsoft-Windows-Windows Defender/Operational"; Name = "Protecao tempo real desabilitada"; Category = "Defesa"; Severity = "High"; Enabled = $true; Description = "Protecao em tempo real desligada." },
    @{ ID = 4104; Log = "Microsoft-Windows-PowerShell/Operational"; Name = "Script Block Logging"; Category = "PowerShell"; Severity = "Medium"; Enabled = $true; Description = "Bloco de script PowerShell registrado." }
)

$eventAlerts = [System.Collections.Generic.List[PSCustomObject]]::new()
$ruleStatistics = @{}
$eventRules | ForEach-Object {
    $ruleStatistics[$_.ID] = @{
        Name  = $_.Name;
        Count = 0;
    }
}

$eventRules | ForEach-Object {
    $rule = $_
    if ($rule.Enabled) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName   = $rule.Log;
                Id        = $rule.ID;
                StartTime = $startDate;
                EndTime   = $endDate;
            } -ErrorAction SilentlyContinue)

            $count = $events.Count
            $ruleStatistics[$rule.ID].Count = $count

            if ($count -gt 0) {
                $sample = @($events | Sort-Object TimeCreated -Descending | Select-Object -First $maxEventsPerRule)

                $sample | ForEach-Object {
                    $evt = $_
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

                    if ($rule.ID -in @(4720, 4732, 1102, 7045, 1116, 5001)) {
                        $eventAlerts.Add([PSCustomObject]@{
                            EventId     = $rule.ID;
                            Rule        = $rule.Name;
                            Category    = $rule.Category;
                            Severity    = $rule.Severity;
                            TimeCreated = $evt.TimeCreated;
                            Computer    = $evt.MachineName;
                            User        = if ($user) { $user } else { "-" };
                            IP          = if ($ip) { $ip } else { "-" };
                            Description = $rule.Description;
                            Message     = $evt.Message;
                        })
                    }
                }
            }
        } 
        catch {}
    }
}

# Deteccao de Forca Bruta (4625)
try {
    $failedLogons = @(Get-WinEvent -FilterHashtable @{ 
        LogName   = "Security";
        Id        = 4625;
        StartTime = $startDate;
        EndTime   = $endDate;
    } -ErrorAction SilentlyContinue)

    $failedLogonObjects = $failedLogons | ForEach-Object {
        $u = Get-EventDataValue -Event $_ -Name "TargetUserName"
        $i = Get-EventDataValue -Event $_ -Name "IpAddress"
        if ([string]::IsNullOrWhiteSpace($i) -or $i -in @("-", "::1", "127.0.0.1")) { 
            $i = "LOCAL" 
        }
        [PSCustomObject]@{
            TimeCreated = $_.TimeCreated;
            User        = $u;
            IP          = $i;
            Computer    = $_.MachineName;
            Message     = $_.Message;
        }
    }

    $groups = $failedLogonObjects | Group-Object User, IP
    $groups | ForEach-Object {
        $group = $_
        $ordered = @($group.Group | Sort-Object TimeCreated)
        if ($ordered.Count -ge $bruteForceThreshold) {
            for ($idx = 0; $idx -lt $ordered.Count; $idx++) {
                $wStart = $ordered[$idx].TimeCreated
                $wEnd   = $wStart.AddMinutes($bruteForceWindowMinutes)
                $wEvts  = @($ordered | Where-Object { $_.TimeCreated -ge $wStart -and $_.TimeCreated -le $wEnd })

                if ($wEvts.Count -ge $bruteForceThreshold) {
                    $first = $wEvts[0]
                    $eventAlerts.Add([PSCustomObject]@{
                        EventId     = 4625;
                        Rule        = "Possivel ataque de forca bruta";
                        Category    = "Autenticacao";
                        Severity    = "High";
                        TimeCreated = $first.TimeCreated;
                        Computer    = $first.Computer;
                        User        = $first.User;
                        IP          = $first.IP;
                        Description = "Detectadas $($wEvts.Count) falhas de autenticacao em janela de $bruteForceWindowMinutes minutos.";
                        Message     = (($wEvts | ForEach-Object { "$($_.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')) - $($_.Message)" }) -join "`r`n");
                    })
                    break
                }
            }
        }
    }
} 
catch {}

# Contas Bloqueadas (4740)
try {
    $lockedEvents = @(Get-WinEvent -FilterHashtable @{ 
        LogName   = "Security";
        Id        = 4740;
        StartTime = $startDate;
        EndTime   = $endDate;
    } -ErrorAction SilentlyContinue | Select-Object -First $maxEventsPerRule)

    $lockedEvents | ForEach-Object {
        $eventAlerts.Add([PSCustomObject]@{
            EventId     = 4740;
            Rule        = "Conta bloqueada";
            Category    = "Autenticacao";
            Severity    = "Medium";
            TimeCreated = $_.TimeCreated;
            Computer    = $_.MachineName;
            User        = (Get-EventDataValue -Event $_ -Name "TargetUserName");
            IP          = "-";
            Description = "Conta bloqueada. Avaliar possivel password spraying.";
            Message     = $_.Message;
        })
    }
} 
catch {}

# PowerShell Script Block (4104)
try {
    $psEvents = @(Get-WinEvent -FilterHashtable @{ 
        LogName   = "Microsoft-Windows-PowerShell/Operational";
        Id        = 4104;
        StartTime = $startDate;
        EndTime   = $endDate;
    } -ErrorAction SilentlyContinue)

    $psPatterns = @(
        "Invoke-Mimikatz", "sekurlsa", "Get-Keystrokes", "DumpCreds",
        "FromBase64String", "EncodedCommand", "DownloadString",
        "Net.WebClient", "Invoke-WebRequest", "IEX", "Invoke-Expression",
        "Reflection.Assembly", "Add-MpPreference", "Set-MpPreference"
    )

    $psEvents | ForEach-Object {
        $msg = $_.Message
        $matched = @($psPatterns | Where-Object { $msg -match [regex]::Escape($_) })
        if ($matched.Count -gt 0) {
            $eventAlerts.Add([PSCustomObject]@{
                EventId     = 4104;
                Rule        = "PowerShell potencialmente suspeito";
                Category    = "PowerShell";
                Severity    = "High";
                TimeCreated = $_.TimeCreated;
                Computer    = $_.MachineName;
                User        = "-";
                IP          = "-";
                Description = "Indicadores suspeitos: " + ($matched -join ", ");
                Message     = $msg;
            })
        }
    }
} 
catch {}

$eventAlerts = @(
    $eventAlerts | Sort-Object @{Expression={Get-SeverityRank $_.Severity};Descending=$true}, @{Expression={$_.TimeCreated};Descending=$true}
)

$totalEventAlerts = $eventAlerts.Count
$critCount = @($eventAlerts | Where-Object { $_.Severity -eq "Critical" }).Count
$highCount = @($eventAlerts | Where-Object { $_.Severity -eq "High" }).Count
$medCount  = @($eventAlerts | Where-Object { $_.Severity -eq "Medium" }).Count
$lowCount  = @($eventAlerts | Where-Object { $_.Severity -eq "Low" }).Count
$infoCount = @($eventAlerts | Where-Object { $_.Severity -eq "Info" }).Count

$eventChartData = @(
    $ruleStatistics.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Label = "$($_.Key) - $($_.Value.Name)";
            Count = $_.Value.Count;
        }
    } | Where-Object { $_.Count -gt 0 } | Sort-Object Count -Descending
)
$eventChartJson = if ($eventChartData.Count -gt 0) { $eventChartData | ConvertTo-Json -Compress } else { "[]" }

$severityChartData = @(
    [PSCustomObject]@{ Label = "Critical"; Count = $critCount },
    [PSCustomObject]@{ Label = "High";     Count = $highCount },
    [PSCustomObject]@{ Label = "Medium";   Count = $medCount },
    [PSCustomObject]@{ Label = "Low";      Count = $lowCount },
    [PSCustomObject]@{ Label = "Info";     Count = $infoCount }
) | Where-Object { $_.Count -gt 0 }
$severityChartJson = if ($severityChartData.Count -gt 0) { $severityChartData | ConvertTo-Json -Compress } else { "[]" }

Write-Host "[2/4] Coletando e analisando Tarefas Agendadas..." -ForegroundColor Cyan

$rawTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
$tasksReport = [System.Collections.Generic.List[PSCustomObject]]::new()

$rawTasks | ForEach-Object {
    $t = $_
    $acts = $t.Actions | Where-Object { $_ -is [Microsoft.Management.Infrastructure.CimInstance] }
    $exec = ($acts | ForEach-Object { $_.Execute }) -join ' ; '
    $args = ($acts | ForEach-Object { $_.Arguments }) -join ' ; '

    $isSusp = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    $isNativeSMB = ($t.TaskPath -like '\Microsoft\Windows\SMB*' -and $args -match 'DisableUnusedSmb1\.ps1')

    if (-not $isNativeSMB) {
        $SuspiciousPathPatterns | ForEach-Object {
            if ($exec -match $_ -or $args -match $_) {
                $isSusp = $true
                $reasons.Add("Caminho em pasta gravavel ($_)")
            }
        }
        $SuspiciousBinaries | ForEach-Object {
            if ($exec -match "(?i)$_") {
                $isSusp = $true
                $reasons.Add("Binario LotL ($_)")
            }
        }
        $SuspiciousArguments | ForEach-Object {
            if ($args -match "(?i)$_") {
                $isSusp = $true
                $reasons.Add("Argumento evasivo ($_)")
            }
        }
    }

    $tasksReport.Add([PSCustomObject]@{
        TaskName     = $t.TaskName;
        TaskPath     = $t.TaskPath;
        State        = $t.State.ToString();
        Author       = if ($t.Author) { $t.Author } else { "N/A" };
        Execute      = if ($exec) { $exec } else { "[COM / Acao Personalizada]" };
        Arguments    = if ($args) { $args } else { "-" };
        IsSuspicious = $isSusp;
        RiskReason   = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" };
    })
}

Write-Host "[3/4] Coletando e analisando Conexoes de Rede..." -ForegroundColor Cyan

$procMap = @{}
Get-CimInstance Win32_Process | ForEach-Object {
    $procMap[$_.ProcessId] = @{
        Name = $_.Name;
        Path = $_.ExecutablePath;
        Cmd  = $_.CommandLine;
    }
}

$SuspiciousPorts = @(4444, 5555, 1337, 31337, 8888, 9999, 6667, 7777, 8081, 9001, 1080)
$connectionsReport = [System.Collections.Generic.List[PSCustomObject]]::new()

$tcpList = Get-NetTCPConnection -ErrorAction SilentlyContinue
$tcpList | ForEach-Object {
    $c = $_
    $p = $procMap[$c.OwningProcess]
    $pName = if ($p.Name) { $p.Name } else { "PID: $($c.OwningProcess)" }
    $pPath = if ($p.Path) { $p.Path } else { "[Inacessivel / Finalizado]" }
    $pCmd  = if ($p.Cmd)  { $p.Cmd }  else { "-" }

    $isSusp = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    $SuspiciousPathPatterns | ForEach-Object {
        if ($pPath -match $_) {
            $isSusp = $true
            $reasons.Add("Binario em pasta gravavel")
        }
    }
    $SuspiciousBinaries | ForEach-Object {
        if ($pName -match "(?i)^$_$") {
            $isSusp = $true
            $reasons.Add("Shell/LotL em rede ($_)")
        }
    }
    if ($SuspiciousPorts -contains [int]$c.RemotePort) {
        $isSusp = $true
        $reasons.Add("Porta remota suspeita ($($c.RemotePort))")
    }

    $connectionsReport.Add([PSCustomObject]@{
        Protocol      = "TCP";
        LocalAddress  = "$($c.LocalAddress):$($c.LocalPort)";
        RemoteAddress = if ($c.RemoteAddress -notin @("0.0.0.0", "::")) { "$($c.RemoteAddress):$($c.RemotePort)" } else { "-" };
        State         = $c.State.ToString();
        PID           = $c.OwningProcess;
        ProcessName   = $pName;
        Path          = $pPath;
        CommandLine   = $pCmd;
        IsSuspicious  = $isSusp;
        RiskReason    = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" };
    })
}

$udpList = Get-NetUDPEndpoint -ErrorAction SilentlyContinue
$udpList | ForEach-Object {
    $u = $_
    $p = $procMap[$u.OwningProcess]
    $pName = if ($p.Name) { $p.Name } else { "PID: $($u.OwningProcess)" }
    $pPath = if ($p.Path) { $p.Path } else { "[Inacessivel / Finalizado]" }
    $pCmd  = if ($p.Cmd)  { $p.Cmd }  else { "-" }

    $isSusp = $false
    $reasons = [System.Collections.Generic.List[string]]::new()

    $SuspiciousPathPatterns | ForEach-Object {
        if ($pPath -match $_) {
            $isSusp = $true
            $reasons.Add("Binario em pasta gravavel")
        }
    }
    $SuspiciousBinaries | ForEach-Object {
        if ($pName -match "(?i)^$_$") {
            $isSusp = $true
            $reasons.Add("Shell/LotL em rede ($_)")
        }
    }

    $connectionsReport.Add([PSCustomObject]@{
        Protocol      = "UDP";
        LocalAddress  = "$($u.LocalAddress):$($u.LocalPort)";
        RemoteAddress = "-";
        State         = "-";
        PID           = $u.OwningProcess;
        ProcessName   = $pName;
        Path          = $pPath;
        CommandLine   = $pCmd;
        IsSuspicious  = $isSusp;
        RiskReason    = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" };
    })
}

Write-Host "[4/4] Coletando e analisando Persistencia no Registro..." -ForegroundColor Cyan

$regTargets = @(
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows\CurrentVersion\Run"; Category = "HKLM Run" },
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows\CurrentVersion\RunOnce"; Category = "HKLM RunOnce" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows\CurrentVersion\Run"; Category = "HKCU Run" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows\CurrentVersion\RunOnce"; Category = "HKCU RunOnce" },
    @{ Hive = "LocalMachine"; Path = "Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Category = "HKLM WoW64 Run" },
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Winlogon"; Category = "Winlogon Hijack" },
    @{ Hive = "CurrentUser";  Path = "Software\Microsoft\Windows NT\CurrentVersion\Winlogon"; Category = "Winlogon User Hijack" },
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"; Category = "IFEO Debugger"; SubkeysOnly = $true },
    @{ Hive = "LocalMachine"; Path = "Software\Microsoft\Windows NT\CurrentVersion\Windows"; Category = "AppInit DLLs" }
)

$registryReport = [System.Collections.Generic.List[PSCustomObject]]::new()

$regTargets | ForEach-Object {
    $target = $_
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$($target.Hive), [Microsoft.Win32.RegistryView]::Registry64)
        $regKey  = $baseKey.OpenSubKey($target.Path)

        if ($regKey) {
            if ($target.SubkeysOnly) {
                $regKey.GetSubKeyNames() | ForEach-Object {
                    $subName = $_
                    $subKey = $regKey.OpenSubKey($subName)
                    if ($subKey) {
                        $vals = $subKey.GetValueNames()
                        if ($vals -contains "Debugger") {
                            $registryReport.Add([PSCustomObject]@{
                                Category     = $target.Category;
                                RegistryPath = "$($target.Hive)\$($target.Path)\$subName";
                                ValueName    = "Debugger";
                                ValueData    = [string]$subKey.GetValue("Debugger");
                                IsSuspicious = $true;
                                RiskReason   = "IFEO Debugger configurado para $subName";
                            })
                        }
                        $subKey.Close()
                    }
                }
            } 
            else {
                $regKey.GetValueNames() | ForEach-Object {
                    $valName = $_
                    $valData = [string]$regKey.GetValue($valName)
                    if (-not [string]::IsNullOrWhiteSpace($valData)) {
                        $isSusp = $false
                        $reasons = [System.Collections.Generic.List[string]]::new()

                        if ($valName -eq "AppInit_DLLs" -and $valData.Trim() -ne "") {
                            $isSusp = $true
                            $reasons.Add("AppInit_DLLs em uso")
                        }
                        if ($target.Category -like "*Winlogon*") {
                            if ($valName -eq "Shell" -and $valData -notmatch '(?i)^explorer\.exe$') {
                                $isSusp = $true
                                $reasons.Add("Shell alterado")
                            }
                            if ($valName -eq "Userinit" -and $valData -notmatch '(?i)^.*system32\\userinit\.exe,') {
                                $isSusp = $true
                                $reasons.Add("Userinit alterado")
                            }
                        }
                        $SuspiciousPathPatterns | ForEach-Object {
                            if ($valData -match $_) {
                                $isSusp = $true
                                $reasons.Add("Referencia a pasta gravavel")
                            }
                        }
                        $SuspiciousBinaries | ForEach-Object {
                            if ($valData -match "(?i)$_") {
                                $isSusp = $true
                                $reasons.Add("Binario LotL ($_)")
                            }
                        }

                        $registryReport.Add([PSCustomObject]@{
                            Category     = $target.Category;
                            RegistryPath = "$($target.Hive)\$($target.Path)";
                            ValueName    = if ($valName -eq "") { "(Padrao)" } else { $valName };
                            ValueData    = $valData;
                            IsSuspicious = $isSusp;
                            RiskReason   = if ($reasons.Count -gt 0) { $reasons -join " | " } else { "Normal" };
                        })
                    }
                }
            }
            $regKey.Close()
        }
        $baseKey.Close()
    } 
    catch {}
}

$suspTasksCount = @($tasksReport | Where-Object { $_.IsSuspicious }).Count
$suspConnCount  = @($connectionsReport | Where-Object { $_.IsSuspicious }).Count
$suspRegCount   = @($registryReport | Where-Object { $_.IsSuspicious }).Count
$totalThreats   = $totalEventAlerts + $suspTasksCount + $suspConnCount + $suspRegCount

Write-Host "[+] Compilando dashboard unificado..." -ForegroundColor Yellow

$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="pt-BR">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('    <meta charset="UTF-8">')
[void]$sb.AppendLine('    <title>Dashboard Integrado de Seguranca</title>')
[void]$sb.AppendLine('    <style>')
[void]$sb.AppendLine('        * { box-sizing: border-box; }')
[void]$sb.AppendLine('        body { margin: 0; padding: 24px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; }')
[void]$sb.AppendLine('        .container { max-width: 1700px; margin: auto; }')
[void]$sb.AppendLine('        .header { background: #1e293b; padding: 22px 28px; border-radius: 12px; border: 1px solid #334155; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }')
[void]$sb.AppendLine('        .header h1 { margin: 0 0 6px 0; font-size: 22px; font-weight: 600; }')
[void]$sb.AppendLine('        .header p { margin: 0; color: #94a3b8; font-size: 13px; }')
[void]$sb.AppendLine('        .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; margin-bottom: 20px; }')
[void]$sb.AppendLine('        .card { background: #1e293b; padding: 16px 20px; border-radius: 10px; border: 1px solid #334155; }')
[void]$sb.AppendLine('        .card-title { font-size: 11px; font-weight: 600; color: #94a3b8; text-transform: uppercase; }')
[void]$sb.AppendLine('        .card-val { font-size: 26px; font-weight: bold; margin-top: 6px; }')
[void]$sb.AppendLine('        .card-val.crit { color: #f87171; }')
[void]$sb.AppendLine('        .card-val.warn { color: #fbbf24; }')
[void]$sb.AppendLine('        .card-val.safe { color: #38bdf8; }')
[void]$sb.AppendLine('        .nav-tabs { display: flex; gap: 8px; border-bottom: 2px solid #334155; margin-bottom: 20px; }')
[void]$sb.AppendLine('        .tab-btn { background: transparent; border: none; padding: 12px 20px; color: #94a3b8; font-weight: 600; font-size: 14px; cursor: pointer; border-bottom: 3px solid transparent; }')
[void]$sb.AppendLine('        .tab-btn.active { color: #38bdf8; border-bottom-color: #38bdf8; }')
[void]$sb.AppendLine('        .tab-btn:hover:not(.active) { color: #cbd5e1; }')
[void]$sb.AppendLine('        .tab-content { display: none; }')
[void]$sb.AppendLine('        .tab-content.active { display: block; }')
[void]$sb.AppendLine('        .grid-charts { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 16px; margin-bottom: 20px; }')
[void]$sb.AppendLine('        .panel { background: #1e293b; padding: 20px; border-radius: 10px; border: 1px solid #334155; }')
[void]$sb.AppendLine('        .panel h2 { margin-top: 0; font-size: 15px; color: #e2e8f0; margin-bottom: 14px; }')
[void]$sb.AppendLine('        .bar-row { display: flex; align-items: center; margin: 8px 0; }')
[void]$sb.AppendLine('        .bar-lbl { width: 220px; font-size: 12px; color: #cbd5e1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }')
[void]$sb.AppendLine('        .bar-wrap { flex: 1; height: 16px; background: #0f172a; border-radius: 4px; overflow: hidden; margin: 0 10px; }')
[void]$sb.AppendLine('        .bar-fill { height: 100%; background: #38bdf8; }')
[void]$sb.AppendLine('        .bar-val { width: 45px; text-align: right; font-size: 12px; font-weight: bold; color: #94a3b8; }')
[void]$sb.AppendLine('        .controls { display: flex; gap: 12px; margin-bottom: 14px; align-items: center; }')
[void]$sb.AppendLine('        input[type="text"] { flex-grow: 1; padding: 10px 14px; border-radius: 6px; border: 1px solid #475569; background: #1e293b; color: #fff; font-size: 13px; outline: none; }')
[void]$sb.AppendLine('        input[type="text"]:focus { border-color: #38bdf8; }')
[void]$sb.AppendLine('        .btn-filter { padding: 9px 16px; border-radius: 6px; border: 1px solid #475569; background: #1e293b; color: #cbd5e1; cursor: pointer; font-size: 12px; font-weight: 500; }')
[void]$sb.AppendLine('        .btn-filter.active { background: #38bdf8; color: #0f172a; border-color: #38bdf8; font-weight: 600; }')
[void]$sb.AppendLine('        table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 8px; overflow: hidden; font-size: 12px; border: 1px solid #334155; }')
[void]$sb.AppendLine('        th { background: #0f172a; text-align: left; padding: 11px 14px; color: #94a3b8; font-weight: 600; border-bottom: 1px solid #334155; }')
[void]$sb.AppendLine('        td { padding: 9px 14px; border-bottom: 1px solid #334155; word-break: break-all; color: #cbd5e1; vertical-align: top; }')
[void]$sb.AppendLine('        tr:hover td { background: #243247; }')
[void]$sb.AppendLine('        tr.suspicious { background: rgba(239, 68, 68, 0.12); }')
[void]$sb.AppendLine('        tr.suspicious:hover td { background: rgba(239, 68, 68, 0.22); }')
[void]$sb.AppendLine('        .badge { display: inline-block; padding: 2px 7px; border-radius: 4px; font-size: 10px; font-weight: bold; text-transform: uppercase; }')
[void]$sb.AppendLine('        .badge-crit { background: #ef4444; color: #fff; }')
[void]$sb.AppendLine('        .badge-high { background: #f97316; color: #fff; }')
[void]$sb.AppendLine('        .badge-med { background: #eab308; color: #000; }')
[void]$sb.AppendLine('        .badge-info { background: #64748b; color: #fff; }')
[void]$sb.AppendLine('        .badge-ok { background: #22c55e; color: #052e16; }')
[void]$sb.AppendLine('        .path { font-family: Consolas, monospace; color: #38bdf8; }')
[void]$sb.AppendLine('        .code { font-family: Consolas, monospace; color: #f1f5f9; }')
[void]$sb.AppendLine('        details { cursor: pointer; }')
[void]$sb.AppendLine('        summary { color: #38bdf8; font-weight: 600; }')
[void]$sb.AppendLine('        pre { background: #0f172a; color: #94a3b8; padding: 10px; border-radius: 6px; max-height: 250px; overflow: auto; white-space: pre-wrap; font-family: Consolas, monospace; font-size: 11px; margin-top: 6px; }')
[void]$sb.AppendLine('    </style>')
[void]$sb.AppendLine('</head>')
[void]$sb.AppendLine('<body>')
[void]$sb.AppendLine('<div class="container">')

[void]$sb.AppendLine('    <div class="header">')
[void]$sb.AppendLine('        <div>')
[void]$sb.AppendLine('            <h1>Dashboard Unificado de Auditoria de Seguranca</h1>')
[void]$sb.AppendLine("            <p>Host: <strong>$($env:COMPUTERNAME)</strong> | Periodo: $($startDate.ToString('dd/MM/yyyy')) ate $($endDate.ToString('dd/MM/yyyy')) | Gerado: $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>")
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('    </div>')

$generalCrit = if ($totalThreats -gt 0) { "crit" } else { "safe" }
[void]$sb.AppendLine('    <div class="cards">')
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Total Alertas EventLog</div><div class='card-val crit'>$totalEventAlerts</div></div>")
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Eventos Criticos</div><div class='card-val crit'>$critCount</div></div>")
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Tarefas Suspeitas</div><div class='card-val warn'>$suspTasksCount</div></div>")
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Conexoes Suspeitas</div><div class='card-val warn'>$suspConnCount</div></div>")
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Persistencia Registro</div><div class='card-val warn'>$suspRegCount</div></div>")
[void]$sb.AppendLine("        <div class='card'><div class='card-title'>Total Geral Ameacas</div><div class='card-val $generalCrit'>$totalThreats</div></div>")
[void]$sb.AppendLine('    </div>')

[void]$sb.AppendLine('    <div class="nav-tabs">')
[void]$sb.AppendLine("        <button class='tab-btn active' onclick='switchTab(""eventsTab"", this)'>Eventos de Seguranca ($totalEventAlerts)</button>")
[void]$sb.AppendLine("        <button class='tab-btn' onclick='switchTab(""tasksTab"", this)'>Tarefas Agendadas ($($tasksReport.Count))</button>")
[void]$sb.AppendLine("        <button class='tab-btn' onclick='switchTab(""connectionsTab"", this)'>Conexoes de Rede ($($connectionsReport.Count))</button>")
[void]$sb.AppendLine("        <button class='tab-btn' onclick='switchTab(""registryTab"", this)'>Persistencia no Registro ($($registryReport.Count))</button>")
[void]$sb.AppendLine('    </div>')

# ABA 1: Eventos
[void]$sb.AppendLine('    <div id="eventsTab" class="tab-content active">')
[void]$sb.AppendLine('        <div class="grid-charts">')
[void]$sb.AppendLine('            <div class="panel"><h2>Severidade dos Alertas</h2><div id="severityChart"></div></div>')
[void]$sb.AppendLine('            <div class="panel"><h2>Eventos Mapeados no Sistema</h2><div id="eventChart"></div></div>')
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <div class="controls">')
[void]$sb.AppendLine('            <input type="text" id="eventSearch" onkeyup="filterGeneric(''eventSearch'', ''tableEvents'')" placeholder="Buscar nos eventos...">')
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <table id="tableEvents">')
[void]$sb.AppendLine('            <thead><tr><th>Severidade</th><th>ID</th><th>Regra / Categoria</th><th>Data/Hora</th><th>Host</th><th>Usuario</th><th>IP</th><th>Detalhes</th></tr></thead>')
[void]$sb.AppendLine('            <tbody>')

$eventAlerts | ForEach-Object {
    $a =$_
    $sevClass = switch ($a.Severity) { "Critical" { "badge-crit" } "High" { "badge-high" } "Medium" { "badge-med" } default { "badge-info" } }
    $trClass  = if ($a.Severity -in @("Critical", "High")) { "suspicious" } else { "normal" }
    $tRule    = [System.Net.WebUtility]::HtmlEncode([string]$a.Rule)
    $tCat     = [System.Net.WebUtility]::HtmlEncode([string]$a.Category)
    $tComp    = [System.Net.WebUtility]::HtmlEncode([string]$a.Computer)
    $tUsr     = [System.Net.WebUtility]::HtmlEncode([string]$a.User)
    $tIp      = [System.Net.WebUtility]::HtmlEncode([string]$a.IP)
    $tDesc    = [System.Net.WebUtility]::HtmlEncode([string]$a.Description)
    $tMsg     = [System.Net.WebUtility]::HtmlEncode([string]$a.Message)

    [void]$sb.AppendLine("                <tr class='$trClass'>")
    [void]$sb.AppendLine("                    <td><span class='badge $sevClass'>$($a.Severity)</span></td>")
    [void]$sb.AppendLine("                    <td><strong>$($a.EventId)</strong></td>")
    [void]$sb.AppendLine("                    <td><strong>$tRule</strong><br><small>$tCat</small></td>")
    [void]$sb.AppendLine("                    <td>$($a.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))</td>")
    [void]$sb.AppendLine("                    <td>$tComp</td>")
    [void]$sb.AppendLine("                    <td>$tUsr</td>")
    [void]$sb.AppendLine("                    <td>$tIp</td>")
    [void]$sb.AppendLine("                    <td><details><summary>Expandir</summary><p>$tDesc</p><pre>$tMsg</pre></details></td>")
    [void]$sb.AppendLine("                </tr>")
}
[void]$sb.AppendLine('            </tbody>')
[void]$sb.AppendLine('        </table>')
[void]$sb.AppendLine('    </div>')

# ABA 2: Tarefas
[void]$sb.AppendLine('    <div id="tasksTab" class="tab-content">')
[void]$sb.AppendLine('        <div class="controls">')
[void]$sb.AppendLine('            <input type="text" id="taskSearch" onkeyup="filterGeneric(''taskSearch'', ''tableTasks'')" placeholder="Buscar por tarefa, pasta, executavel ou comando...">')
[void]$sb.AppendLine('            <button class="btn-filter" id="btnTaskSusp" onclick="toggleSuspiciousOnly(''tableTasks'', this)">Apenas Suspeitas</button>')
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <table id="tableTasks">')
[void]$sb.AppendLine('            <thead><tr><th>Status</th><th>Nome da Tarefa</th><th>Caminho</th><th>Binario / Executavel</th><th>Argumentos</th><th>Diagnostico</th></tr></thead>')
[void]$sb.AppendLine('            <tbody>')

$tasksReport | ForEach-Object {
    $t =$_
    $trClass = if ($t.IsSuspicious) { "suspicious" } else { "normal" }
    $badge   = if ($t.IsSuspicious) { "<span class='badge badge-crit'>Alerta</span>" } else { "<span class='badge badge-ok'>OK</span>" }
    $tName   = [System.Net.WebUtility]::HtmlEncode([string]$t.TaskName)
    $tPath   = [System.Net.WebUtility]::HtmlEncode([string]$t.TaskPath)
    $tExec   = [System.Net.WebUtility]::HtmlEncode([string]$t.Execute)
    $tArgs   = [System.Net.WebUtility]::HtmlEncode([string]$t.Arguments)
    $tRisk   = [System.Net.WebUtility]::HtmlEncode([string]$t.RiskReason)
    $isSusp  =$t.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("                <tr class='$trClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                    <td>$badge</td>")
    [void]$sb.AppendLine("                    <td><strong>$tName</strong></td>")
    [void]$sb.AppendLine("                    <td class='path'>$tPath</td>")
    [void]$sb.AppendLine("                    <td class='code'>$tExec</td>")
    [void]$sb.AppendLine("                    <td class='code'>$tArgs</td>")
    [void]$sb.AppendLine("                    <td>$tRisk</td>")
    [void]$sb.AppendLine("                </tr>")
}
[void]$sb.AppendLine('            </tbody>')
[void]$sb.AppendLine('        </table>')
[void]$sb.AppendLine('    </div>')

# ABA 3: Conexoes
[void]$sb.AppendLine('    <div id="connectionsTab" class="tab-content">')
[void]$sb.AppendLine('        <div class="controls">')
[void]$sb.AppendLine('            <input type="text" id="connSearch" onkeyup="filterGeneric(''connSearch'', ''tableConns'')" placeholder="Buscar por IP, porta, executavel, PID ou processo...">')
[void]$sb.AppendLine('            <button class="btn-filter" id="btnConnSusp" onclick="toggleSuspiciousOnly(''tableConns'', this)">Apenas Suspeitas</button>')
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <table id="tableConns">')
[void]$sb.AppendLine('            <thead><tr><th>Status</th><th>Proto</th><th>Endereco Local</th><th>Endereco Remoto</th><th>PID</th><th>Processo</th><th>Linha de Comando</th><th>Diagnostico</th></tr></thead>')
[void]$sb.AppendLine('            <tbody>')

$connectionsReport | ForEach-Object {
    $c =$_
    $trClass = if ($c.IsSuspicious) { "suspicious" } else { "normal" }
    $badge   = if ($c.IsSuspicious) { "<span class='badge badge-crit'>Alerta</span>" } else { "<span class='badge badge-ok'>OK</span>" }
    $pName   = [System.Net.WebUtility]::HtmlEncode([string]$c.ProcessName)
    $pCmd    = [System.Net.WebUtility]::HtmlEncode([string]$c.CommandLine)
    $cRisk   = [System.Net.WebUtility]::HtmlEncode([string]$c.RiskReason)
    $isSusp  =$c.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("                <tr class='$trClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                    <td>$badge</td>")
    [void]$sb.AppendLine("                    <td><strong>$($c.Protocol)</strong></td>")
    [void]$sb.AppendLine("                    <td class='code'>$($c.LocalAddress)</td>")
    [void]$sb.AppendLine("                    <td class='code'>$($c.RemoteAddress)</td>")
    [void]$sb.AppendLine("                    <td>$($c.PID)</td>")
    [void]$sb.AppendLine("                    <td><strong>$pName</strong></td>")
    [void]$sb.AppendLine("                    <td class='code'>$pCmd</td>")
    [void]$sb.AppendLine("                    <td>$cRisk</td>")
    [void]$sb.AppendLine("                </tr>")
}
[void]$sb.AppendLine('            </tbody>')
[void]$sb.AppendLine('        </table>')
[void]$sb.AppendLine('    </div>')

# ABA 4: Registro
[void]$sb.AppendLine('    <div id="registryTab" class="tab-content">')
[void]$sb.AppendLine('        <div class="controls">')
[void]$sb.AppendLine('            <input type="text" id="regSearch" onkeyup="filterGeneric(''regSearch'', ''tableReg'')" placeholder="Buscar por chave, valor, arquivo ou argumento...">')
[void]$sb.AppendLine('            <button class="btn-filter" id="btnRegSusp" onclick="toggleSuspiciousOnly(''tableReg'', this)">Apenas Suspeitas</button>')
[void]$sb.AppendLine('        </div>')
[void]$sb.AppendLine('        <table id="tableReg">')
[void]$sb.AppendLine('            <thead><tr><th>Status</th><th>Categoria</th><th>Caminho Chave</th><th>Nome do Valor</th><th>Dados / Comando</th><th>Diagnostico</th></tr></thead>')
[void]$sb.AppendLine('            <tbody>')

$registryReport | ForEach-Object {
    $r =$_
    $trClass = if ($r.IsSuspicious) { "suspicious" } else { "normal" }
    $badge   = if ($r.IsSuspicious) { "<span class='badge badge-crit'>Alerta</span>" } else { "<span class='badge badge-ok'>OK</span>" }
    $rCat    = [System.Net.WebUtility]::HtmlEncode([string]$r.Category)
    $rPath   = [System.Net.WebUtility]::HtmlEncode([string]$r.RegistryPath)
    $rName   = [System.Net.WebUtility]::HtmlEncode([string]$r.ValueName)
    $rData   = [System.Net.WebUtility]::HtmlEncode([string]$r.ValueData)
    $rRisk   = [System.Net.WebUtility]::HtmlEncode([string]$r.RiskReason)
    $isSusp  =$r.IsSuspicious.ToString().ToLower()

    [void]$sb.AppendLine("                <tr class='$trClass' data-suspicious='$isSusp'>")
    [void]$sb.AppendLine("                    <td>$badge</td>")
    [void]$sb.AppendLine("                    <td>$rCat</td>")
    [void]$sb.AppendLine("                    <td class='path'>$rPath</td>")
    [void]$sb.AppendLine("                    <td><strong>$rName</strong></td>")
    [void]$sb.AppendLine("                    <td class='code'>$rData</td>")
    [void]$sb.AppendLine("                    <td>$rRisk</td>")
    [void]$sb.AppendLine("                </tr>")
}
[void]$sb.AppendLine('            </tbody>')
[void]$sb.AppendLine('        </table>')
[void]$sb.AppendLine('    </div>')

[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('<script>')
[void]$sb.AppendLine("    const severityData = $severityChartJson;")
[void]$sb.AppendLine("    const eventData    = $eventChartJson;")

[void]$sb.AppendLine('    function switchTab(tabId, btn) {')
[void]$sb.AppendLine('        document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));')
[void]$sb.AppendLine('        document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));')
[void]$sb.AppendLine('        document.getElementById(tabId).classList.add("active");')
[void]$sb.AppendLine('        btn.classList.add("active");')
[void]$sb.AppendLine('    }')

[void]$sb.AppendLine('    function renderBars(containerId, data) {')
[void]$sb.AppendLine('        const el = document.getElementById(containerId);')
[void]$sb.AppendLine('        if (!el || !data || data.length === 0) { el.innerHTML = "<p style=''color:#64748b''>Nenhum dado.</p>"; return; }')
[void]$sb.AppendLine('        let max = Math.max(...data.map(d => d.Count));')
[void]$sb.AppendLine('        el.innerHTML = data.map(d => `')
[void]$sb.AppendLine('            <div class="bar-row">')
[void]$sb.AppendLine('                <div class="bar-lbl" title="${d.Label}">${d.Label}</div>')
[void]$sb.AppendLine('                <div class="bar-wrap"><div class="bar-fill" style="width:${(d.Count/max)*100}%"></div></div>')
[void]$sb.AppendLine('                <div class="bar-val">${d.Count}</div>')
[void]$sb.AppendLine('            </div>`).join("");')
[void]$sb.AppendLine('    }')

[void]$sb.AppendLine('    function filterGeneric(inputId, tableId) {')
[void]$sb.AppendLine('        const query = document.getElementById(inputId).value.toLowerCase();')
[void]$sb.AppendLine('        const rows = document.querySelectorAll("#" + tableId + " tbody tr");')
[void]$sb.AppendLine('        rows.forEach(r => {')
[void]$sb.AppendLine('            const matches = r.innerText.toLowerCase().includes(query);')
[void]$sb.AppendLine('            const isSuspFilter = r.getAttribute("data-filter-susp") === "true";')
[void]$sb.AppendLine('            r.style.display = (matches && !isSuspFilter) ? "" : "none";')
[void]$sb.AppendLine('        });')
[void]$sb.AppendLine('    }')

[void]$sb.AppendLine('    function toggleSuspiciousOnly(tableId, btn) {')
[void]$sb.AppendLine('        btn.classList.toggle("active");')
[void]$sb.AppendLine('        const active = btn.classList.contains("active");')
[void]$sb.AppendLine('        const rows = document.querySelectorAll("#" + tableId + " tbody tr");')
[void]$sb.AppendLine('        rows.forEach(r => {')
[void]$sb.AppendLine('            const isSusp = r.getAttribute("data-suspicious") === "true";')
[void]$sb.AppendLine('            r.setAttribute("data-filter-susp", (active && !isSusp) ? "true" : "false");')
[void]$sb.AppendLine('            r.style.display = (active && !isSusp) ? "none" : "";')
[void]$sb.AppendLine('        });')
[void]$sb.AppendLine('    }')

[void]$sb.AppendLine('    renderBars("severityChart", severityData);')
[void]$sb.AppendLine('    renderBars("eventChart", eventData);')
[void]$sb.AppendLine('</script>')
[void]$sb.AppendLine('</body>')
[void]$sb.AppendLine('</html>')

$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(),$utf8WithBom)

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Green
Write-Host "[OK] Dashboard Consolidado gerado com sucesso!" -ForegroundColor Green
Write-Host "Arquivo: $OutputPath" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Green
Write-Host "Resumo de Alertas Encontrados:"
Write-Host " - Eventos de Seguranca : $totalEventAlerts (Criticos: $critCount \vert{} Altos:$highCount)"
Write-Host " - Tarefas Agendadas    : $suspTasksCount suspeitas"
Write-Host " - Conexoes de Rede     : $suspConnCount suspeitas"
Write-Host " - Persistencia Registro: $suspRegCount suspeitas"
Write-Host ""

Invoke-Item $OutputPath
