# Slack webhook URL and VirusTotal API key values
$slackWebhookUrl = "https://discord.com/api/webhooks/1429592953692749976/JTeF7oOI01Khgvot3El_Y_EMQ9_WMY0uHZLPuKcEl5Y15PH44vTZIOerDXx9Oq5mkECL"
$virusTotalApiKey = "71dc3a121eb1ae409f03ab97ccd73ea5f396a4a7744b89c2d575acc7f0db1d1c"


# Get running process list
$processes = Get-Process

# Process each running process
$results = foreach ($process in $processes) {

    try {
        # Get process executable path
        $filePath = $process.MainModule.FileName

        if ($filePath -and (Test-Path $filePath)) {

            # Calculate SHA256 of the actual executable
            $hash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash

            # Create object
            [PSCustomObject]@{
                'Process Name' = $process.Name
                'File Path'    = $filePath
                'SHA256 Hash'  = $hash
            }
        }
    }
    catch {
        # Some processes cannot be accessed without administrator privileges
        Write-Verbose "Não foi possível acessar $($process.Name): $($_.Exception.Message)"
    }
}

# Remove duplicate hashes
$uniqueResults = $results |
    Group-Object -Property 'SHA256 Hash' |
    ForEach-Object {
        $_.Group | Select-Object -First 1
    }

# Check each unique hash with VirusTotal
foreach ($result in $uniqueResults) {

    $hash = $result.'SHA256 Hash'

    Write-Host "Consultando: $($result.'Process Name')"
    Write-Host "Hash: $hash"

    try {

        # VirusTotal API
        $vtResponse = curl.exe -s `
            -H "x-apikey: $virusTotalApiKey" `
            "https://www.virustotal.com/api/v3/files/$hash"

        # Convert JSON response to PowerShell object
        $vtData = $vtResponse | ConvertFrom-Json

        # Check if VirusTotal returned an error
        if ($vtData.error) {
            Write-Host "VirusTotal: $($vtData.error.message)" -ForegroundColor Yellow
            continue
        }

        # Number of malicious detections
        $malicious = $vtData.data.attributes.last_analysis_stats.malicious

        if ($malicious -gt 0) {

            Write-Host "ALERTA: $($result.'Process Name') - $malicious detecções" -ForegroundColor Red

            # Slack message
            $slackMessage = @{
                text = @"
Suspicious Process Found!

Process Name: $($result.'Process Name')
Executable Path: $($result.'File Path')
SHA256: $hash
VirusTotal Malicious Detections: $malicious
"@
            }

            Invoke-RestMethod `
                -Method Post `
                -Uri $slackWebhookUrl `
                -ContentType "application/json" `
                -Body ($slackMessage | ConvertTo-Json)
        }
    }
    catch {
        Write-Host "Erro ao consultar $hash : $($_.Exception.Message)" -ForegroundColor Red
    }
}
