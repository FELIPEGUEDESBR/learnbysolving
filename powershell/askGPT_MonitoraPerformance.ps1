Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. ./NoScale.ps1

###################################################
###              Summary Function               ###
###################################################


Function Get-MetricSummaryText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject[]]$MetricHistory,
        [INT]$HighUsageThreshold = 80
    )


    # Extract values
    $CPUValues  = $MetricHistory.CPUPercent
    $DiskValues = $MetricHistory.DiskPercent
    $MemoryValues = $MetricHistory.MemoryPercent

    # Time window
    $StartTime = ($MetricHistory | Select-Object -First 1).TimeStamp
    $EndTime   = ($MetricHistory | Select-Object -Last 1).TimeStamp
    $Samples   = $MetricHistory.Count


    # Helper function within a function for basic stats
    Function Get-Stats {
        param ([double[]]$Values)
        $Measure = $Values | Measure-Object -Average -Minimum -Maximum
        Return @{
            Average     = [Math]::Round($Measure.Average, 2)
            Min         = $Measure.Minimum
            Max         = $Measure.Maximum
            HighPercent = [Math]::Round(
                (($Values | Where-Object { $_ -ge $HighUsageThreshold }).Count / $Values.Count) * 100,1)
        }
    }

    $CpuStats  = Get-Stats -Values $CPUValues
    $DiskStats = Get-Stats -Values $DiskValues
    $MemoryStats = Get-Stats -Values $MemoryValues


    # Uptime (latest sample)
    $UpTime = ($MetricHistory | Select-Object -Last 1).UpTime


##### Build AI-friendly summary text


    $SummaryText = @"

SYSTEM PERFORMANCE SUMMARY

Observation Window: $StartTime to $EndTime

Total Number of Samples Collected: $Samples


CPU UTILIZATION

    Average Usage: $($CpuStats.Average)% 


    Peak Usage: $($CpuStats.Max)% 


    Minimum Usage: $($CpuStats.Min)% 


    Time spent at $HighUsageThreshold% or higher utilization: $($CpuStats.HighPercent)% 



DISK UTILIZATION

    Average Usage: $($DiskStats.Average)% 


    Peak Usage: $($DiskStats.Max)% 


    Minimum Usage: $($DiskStats.Min)% 


    Time spent at $HighUsageThreshold% or higher utilization: $($DiskStats.HighPercent)% 



SYSTEM UPTIME

    Current Uptime: $UpTime 


"@


    Return $SummaryText.Trim()

}


###################################################

###                  Main Body                  ###

###################################################


# Create main form
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "AI System Performance Analyst"
$Form.Size = New-Object System.Drawing.Size(1920, 1080)
$Form.StartPosition = "Manual"
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$Form.ForeColor = [System.Drawing.Color]::White
$Form.FormBorderStyle = 'FixedSingle'
$Form.MaximizeBox = $False

$GLobal:MetricHistory = @()



#################################
###          Header           ###
#################################

$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Size = New-Object System.Drawing.Size(1920, 80)
$HeaderPanel.Location = New-Object System.Drawing.Point(0, 0)
$HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)

$HeaderLabel = New-Object System.Windows.Forms.Label
$HeaderLabel.Text = "AI-Integrated System Performance Dashboard"
$HeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$HeaderLabel.AutoSize = $True
$HeaderLabel.Location = New-Object System.Drawing.Point(20, 20)


$headerPanel.Controls.Add($headerLabel)

$form.Controls.Add($headerPanel)


#################################
###    Live Metrics Panel     ###
#################################


$MetricsPanel = New-Object System.Windows.Forms.Panel
$MetricsPanel.Size = New-Object System.Drawing.Size(600, 650)
$MetricsPanel.Location = New-Object System.Drawing.Point(20, 100)
$MetricsPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)


$MetricsTitle = New-Object System.Windows.Forms.Label
$MetricsTitle.Text = "Live System Metrics"
$MetricsTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$MetricsTitle.AutoSize = $True
$MetricsTitle.Location = New-Object System.Drawing.Point(20, 20)


$MetricsCPULabel = New-Object System.Windows.Forms.Label
$MetricsCPULabel.Text = "CPU Usage: --"
$MetricsCPULabel.Font = New-Object System.Drawing.Font("Arial", 14)
$MetricsCPULabel.AutoSize = $True
$MetricsCPULabel.Location = New-Object System.Drawing.Point(20, 80)


$MetricsMemoryLabel = New-Object System.Windows.Forms.Label
$MetricsMemoryLabel.Text = "Memory Use: --"
$MetricsMemoryLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$MetricsMemoryLabel.AutoSize = $True
$MetricsMemoryLabel.Location = New-Object System.Drawing.Point(20, 130)


$MetricsDiskLabel = New-Object System.Windows.Forms.Label
$MetricsDiskLabel.Text = "Disk Activity: --"
$MetricsDiskLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$MetricsDiskLabel.AutoSize = $True
$MetricsDiskLabel.Location = New-Object System.Drawing.Point(20, 180)


$MetricsUptimeLabel = New-Object System.Windows.Forms.Label
$MetricsUptimeLabel.Text = "System Uptime: --"
$MetricsUptimeLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$MetricsUptimeLabel.AutoSize = $True
$MetricsUptimeLabel.Location = New-Object System.Drawing.Point(20, 230)


$MetricsPanel.Controls.Add($MetricsTitle)
$MetricsPanel.Controls.Add($MetricsCPULabel)
$MetricsPanel.Controls.Add($MetricsMemoryLabel)
$MetricsPanel.Controls.Add($MetricsDiskLabel)

$MetricsPanel.Controls.Add($MetricsUptimeLabel)


#################################

###   Hardware Specifications ###

#################################


$HardwareTitle = New-Object System.Windows.Forms.Label

$HardwareTitle.Text = "Hardware Specifications"

$HardwareTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)

$HardwareTitle.AutoSize = $True

$HardwareTitle.Location = New-Object System.Drawing.Point(20, 380)


$HardwareMemory = New-Object System.Windows.Forms.Label

$HardwareMemory.Text = "Installed Memory (RAM): --"

$HardwareMemory.Font = New-Object System.Drawing.Font("Arial", 12)

$HardwareMemory.AutoSize = $True

$HardwareMemory.Location = New-Object System.Drawing.Point(20, 450)


$HardwareDisk = New-Object System.Windows.Forms.Label

$HardwareDisk.Text = "Total Disk Capacity: --"

$HardwareDisk.Font = New-Object System.Drawing.Font("Arial", 12)

$HardwareDisk.AutoSize = $True

$HardwareDisk.Location = New-Object System.Drawing.Point(20, 500)


$HardwareCPU = New-Object System.Windows.Forms.Label

$HardwareCPU.Text = "CPU Model: --"

$HardwareCPU.Font = New-Object System.Drawing.Font("Arial", 12)

$HardwareCPU.AutoSize = $True

$HardwareCPU.Location = New-Object System.Drawing.Point(20, 550)


$HardwareGPU = New-Object System.Windows.Forms.Label

$HardwareGPU.Text = "GPU Model: --"

$HardwareGPU.Font = New-Object System.Drawing.Font("Arial", 12)

$HardwareGPU.AutoSize = $True

$HardwareGPU.Location = New-Object System.Drawing.Point(20, 600)


$MetricsPanel.Controls.Add($HardwareTitle)

$MetricsPanel.Controls.Add($HardwareMemory)

$MetricsPanel.Controls.Add($HardwareDisk)

$MetricsPanel.Controls.Add($HardwareCPU)

$MetricsPanel.Controls.Add($HardwareGPU)


$Form.Controls.Add($MetricsPanel)


#################################

### Right Panel - AI Analysis ###

#################################


$AnalysisPanel = New-Object System.Windows.Forms.Panel

$AnalysisPanel.Size = New-Object System.Drawing.Size(1240, 650)

$AnalysisPanel.Location = New-Object System.Drawing.Point(660, 100)

$AnalysisPanel.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 35)


$AnalysisTitle = New-Object System.Windows.Forms.Label

$AnalysisTitle.Text = "AI Analysis & Recommendations"

$AnalysisTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)

$AnalysisTitle.AutoSize = $true

$AnalysisTitle.Location = New-Object System.Drawing.Point(20, 20)


$AnalysisAssessmentSectionLabel = New-Object System.Windows.Forms.Label

$AnalysisAssessmentSectionLabel.Text = "Current Assessment and Observations"

$AnalysisAssessmentSectionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

$AnalysisAssessmentSectionLabel.AutoSize = $True

$AnalysisAssessmentSectionLabel.Location = New-Object System.Drawing.Point(20, 80)


$AnalysisAssessmentSectionBox = New-Object System.Windows.Forms.RichTextBox

$AnalysisAssessmentSectionBox.Multiline = $True

$AnalysisAssessmentSectionBox.ReadOnly = $True

$AnalysisAssessmentSectionBox.ScrollBars = "Vertical"

$AnalysisAssessmentSectionBox.Size = New-Object System.Drawing.Size(1180, 100)

$AnalysisAssessmentSectionBox.Location = New-Object System.Drawing.Point(20, 130)

$AnalysisAssessmentSectionBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)

$AnalysisAssessmentSectionBox.ForeColor = [System.Drawing.Color]::White

$AnalysisAssessmentSectionBox.Font = New-Object System.Drawing.Font("Arial", 14)


$AnalysisSectionRisksLabel = New-Object System.Windows.Forms.Label

$AnalysisSectionRisksLabel.Text = "Identified Risks"

$AnalysisSectionRisksLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

$AnalysisSectionRisksLabel.AutoSize = $True

$AnalysisSectionRisksLabel.Location = New-Object System.Drawing.Point(20, 250)


$AnalysisRisksSectionBox = New-Object System.Windows.Forms.RichTextBox

$AnalysisRisksSectionBox.Multiline = $True

$AnalysisRisksSectionBox.ReadOnly = $True

$AnalysisRisksSectionBox.ScrollBars = "Vertical"

$AnalysisRisksSectionBox.Size = New-Object System.Drawing.Size(1180, 100)

$AnalysisRisksSectionBox.Location = New-Object System.Drawing.Point(20, 300)

$AnalysisRisksSectionBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)

$AnalysisRisksSectionBox.ForeColor = [System.Drawing.Color]::White

$AnalysisRisksSectionBox.Font = New-Object System.Drawing.Font("Arial", 14)


$AnalysisRecommendationsSectionLabel = New-Object System.Windows.Forms.Label

$AnalysisRecommendationsSectionLabel.Text = "AI Recommendations"

$AnalysisRecommendationsSectionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

$AnalysisRecommendationsSectionLabel.AutoSize = $True

$AnalysisRecommendationsSectionLabel.Location = New-Object System.Drawing.Point(20, 400)


$AnalysisRecommendationsSectionBox = New-Object System.Windows.Forms.RichTextBox

$AnalysisRecommendationsSectionBox.Multiline = $True

$AnalysisRecommendationsSectionBox.ReadOnly = $True

$AnalysisRecommendationsSectionBox.ScrollBars = "Vertical"

$AnalysisRecommendationsSectionBox.Size = New-Object System.Drawing.Size(1180, 100)

$AnalysisRecommendationsSectionBox.Location = New-Object System.Drawing.Point(20, 450)

$AnalysisRecommendationsSectionBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)

$AnalysisRecommendationsSectionBox.ForeColor = [System.Drawing.Color]::White

$AnalysisRecommendationsSectionBox.Font = New-Object System.Drawing.Font("Arial", 14)


$ExitButton = New-Object System.Windows.Forms.Button

$ExitButton.Text = "Exit"

$ExitButton.Size = New-Object System.Drawing.Size(200,40)

$ExitButton.Location = New-Object System.Drawing.Point(700,600)

$ExitButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)


$ExitButton.Add_Click({

    $Timer.Stop()

    $ResultTimer.Stop()


    if ($Script:MetricJob) {

        Stop-Job $Script:MetricJob -Force -ErrorAction SilentlyContinue

        Remove-Job $Script:MetricJob -Force -ErrorAction SilentlyContinue

    }


    $Form.Close()

    $Form.Dispose()

})


###################################################

###                   Analyze                   ###

###################################################


$AnalyzeButton = New-Object System.Windows.Forms.Button
$AnalyzeButton.Text = "Analyze"
$AnalyzeButton.Size = New-Object System.Drawing.Size(200,40)
$AnalyzeButton.Location = New-Object System.Drawing.Point(1000,600)
$AnalyzeButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)

$AnalyzeButton.Add_Click({
$Timer.Stop()
$MetricSummaryText = Get-MetricSummaryText -MetricHistory $MetricHistory
$SystemRole = "You are an AI based analytical tool, analyzing Windows performance data"
$Instructions = "Please provide any general observations or insights about this system's performance based on the summary provided. Please keep the output short and limited to a sentence or two. Be concise and technical. Here is the summary data:"

###### Get General Observations ####


$Prompt = @(
$SystemRole
$Instructions
$HardwareSummary
$MetricSummaryText
) -join "`n`n"


$Body = @{
    Model  = "Llama3"
    Prompt = $Prompt
    Stream = $False
} | ConvertTo-Json


Try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body


    $AnalysisAssessmentSectionBox.Text =$Response.Response.Trim()

}

Catch {

    Return "ERROR: Unable to contact Ollama"

}


###### Get Identified Risks ####

$Instructions = "Please tell me about any risks that may exist based on this system's performance data. Please keep the output short and limited to a sentence or two. Be concise and technical. Here is the summary data:"

$Prompt = @(
$SystemRole
$Instructions
$HardwareSummary
$MetricSummaryText

) -join "`n`n"



    $Body = @{
        Model  = "Llama3"
        Prompt = $Prompt
        Stream = $False
    } | ConvertTo-Json


    Try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body


    $AnalysisRisksSectionBox.Text =$Response.Response.Trim()

    }

    Catch {
    Return "ERROR: Unable to contact Ollama"

    }


###### Get Tuning Recommendations ####

$Instructions = "Please provide me a short, concise, and technical answer to my question. The answer should be based on the suwith any tuning recommendations that you may have, based on this system's performance data. Please keep the output short, limited to a sentence or two. Be concise and technical. Here is the summary data:"

$Prompt = @(
$SystemRole
$Instructions
$HardwareSummary
$MetricSummaryText
) -join "`n`n"

    $Body = @{
        Model  = "Llama3"
        Prompt = $Prompt
        Stream = $False
    } | ConvertTo-Json


Try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body


    $AnalysisRecommendationsSectionBox.Text =$Response.Response.Trim()

}

Catch {

    Return "ERROR: Unable to contact Ollama"

}
$Timer.Start()
})


$AnalysisPanel.Controls.Add($AnalysisTitle)
$AnalysisPanel.Controls.Add($AnalysisAssessmentSectionLabel)
$AnalysisPanel.Controls.Add($AnalysisAssessmentSectionBox)
$AnalysisPanel.Controls.Add($AnalysisSectionRisksLabel)
$AnalysisPanel.Controls.Add($AnalysisRisksSectionBox)
$AnalysisPanel.Controls.Add($AnalysisRecommendationsSectionLabel)
$AnalysisPanel.Controls.Add($AnalysisRecommendationsSectionBox)
$AnalysisPanel.Controls.Add($AnalyzeButton)
$AnalysisPanel.Controls.Add($ExitButton)

$Form.Controls.Add($AnalysisPanel)


#################################

###       Answers Panel       ###

#################################


$AnswerPanel = New-Object System.Windows.Forms.Panel
$AnswerPanel.Size = New-Object System.Drawing.Size(1900, 150)
$AnswerPanel.Location = New-Object System.Drawing.Point(20, 750)
$AnswerPanel.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 35)

$AnswerSectionLabel = New-Object System.Windows.Forms.Label
$AnswerSectionLabel.Text = "Answers to Your Questions"
$AnswerSectionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$AnswerSectionLabel.AutoSize = $True
$AnswerSectionLabel.Location = New-Object System.Drawing.Point(20, 0)

$AnswerSectionBox = New-Object System.Windows.Forms.RichTextBox
$AnswerSectionBox.Multiline = $True
$AnswerSectionBox.ReadOnly = $True
$AnswerSectionBox.ScrollBars = "Vertical"
$AnswerSectionBox.Size = New-Object System.Drawing.Size(1850, 100)
$AnswerSectionBox.Location = New-Object System.Drawing.Point(20, 50)
$AnswerSectionBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$AnswerSectionBox.ForeColor = [System.Drawing.Color]::White
$AnswerSectionBox.Font = New-Object System.Drawing.Font("Arial", 14)

$AnswerPanel.Controls.Add($AnswerSectionLabel)
$AnswerPanel.Controls.Add($AnswerSectionBox)

$Form.Controls.Add($AnswerPanel)


#################################

### Bottom Panel - Ask a Question ###

#################################


$InputPanel = New-Object System.Windows.Forms.Panel
$InputPanel.Size = New-Object System.Drawing.Size(1850, 80)
$InputPanel.Location = New-Object System.Drawing.Point(20, 925)
$InputPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)

$InputBox = New-Object System.Windows.Forms.TextBox
$InputBox.Size = New-Object System.Drawing.Size(1600, 40)
$InputBox.Location = New-Object System.Drawing.Point(20, 20)
$InputBox.Font = New-Object System.Drawing.Font("Segoe UI", 14)
$InputBox.PlaceholderText = "Ask the performance analyst a question..."


$AskButton = New-Object System.Windows.Forms.Button
$AskButton.Text = "Ask"
$AskButton.Size = New-Object System.Drawing.Size(200, 40)
$AskButton.Location = New-Object System.Drawing.Point(1640, 20)
$AskButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)


$InputPanel.Controls.Add($InputBox)
$InputPanel.Controls.Add($AskButton)

$Form.Controls.Add($InputPanel)

$AskButton.Add_Click({$Timer.Stop()

    $MetricSummaryText = Get-MetricSummaryText -MetricHistory $MetricHistory
    $SystemRole = "You are an AI based analytical tool, analyzing Windows performance data"
    $Instructions = "I have a question. Please base your answer on the system performance summary data that I am providing. Here is the summary data:"
    $Question = "My question is " + $InputBox.Text


###### Ask a Question ####

$Prompt = @($SystemRole
$Instructions
$HardwareSummary
$MetricSummaryText
$Question

) -join "`n`n"



    $Body = @{

        Model  = "Llama3"
        Prompt = $Prompt
        Stream = $False
    } | ConvertTo-Json


Try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:11434/api/generate" `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body


    $AnswerSectionBox.Text =$Response.Response.Trim()

}

Catch {

    Return "ERROR: Unable to contact Ollama"

}
$InputBox.Text = ""
$Timer.Start()
})

 




#############################################

###   Load Hardware Specifications        ###

#############################################


# CPU
$CPU = Get-CimInstance Win32_Processor | Select-Object -First 1
$HardwareCPU.Text = "CPU: $($CPU.Name)"

# RAM
$RAMGB = [Math]::Round(
    (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1

)
$HardwareMemory.Text = "Installed Memory (RAM): $RAMGB GB"

# Disk (total of all fixed drives)
$Drive = Get-PSDrive C
$DiskTotal = ($Drive.Used + $Drive.Free) / 1048576
$DiskGB = "{0:N1}" -f $DiskTotal    # This formats the output to include commas and to limit the output to a single decimal position
$HardwareDisk.Text = "Total Disk Capacity: $DiskGB GB"


# GPU
$GPU = Get-CimInstance Win32_VideoController | Select-Object -Last 1
$HardwareGPU.Text = "GPU: $($GPU.Name)"


###### Create Hardware Summary that will become part of the AI prompt ####
$HardwareSummary = @"
HARDWARE SUMMARY
This is a summary of the computer's hardware configuration:
CPU Type: $CPU
Total Memory: $RAMGB
Total Size of the C: Volume: $DiskTotal GB
Free disk space: $Drive.Free Bytes
GPU Type: $GPU
"@


#############################################

###   Gather Real Time Metrics            ###

#############################################

# Flags
$Script:JobRunning = $false
$Script:MetricJob = $null

# Timer 1: Starts background job
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 5000  # 5 seconds
$Timer.Add_Tick({


    if ($Script:JobRunning) { return }
    $Script:JobRunning = $true
    $Script:MetricJob = Start-Job -ScriptBlock {


        # CPU usage
        $CPU = (Get-Counter '\Processador(_Total)\% tempo de processador').CounterSamples.CookedValue


        # Memory usage
        $OS = Get-CimInstance Win32_OperatingSystem
        $TotalMemory = $OS.TotalVisibleMemorySize
        $FreeMemory = $OS.FreePhysicalMemory
        $MemoryUsedPercent = (($TotalMemory - $FreeMemory) / $TotalMemory) * 100


        # Disk activity
        $Disk = (Get-Counter '\PhysicalDisk(1 C:)\% tempo de disco').CounterSamples.CookedValue


        # Uptime
        $Uptime = (Get-Date) - $OS.LastBootUpTime


        # Return results
        return [PSCustomObject]@{

            CPU    = $CPU
            Memory = $MemoryUsedPercent
            Disk   = $Disk
            Uptime = $Uptime

        }

    }

})



# Timer 2: Polls job and updates UI

$ResultTimer = New-Object System.Windows.Forms.Timer
$ResultTimer.Interval = 500

$ResultTimer.Add_Tick({

    if ($Script:MetricJob -and $Script:MetricJob.State -eq 'Completed') {
        $Result = Receive-Job $Script:MetricJob
        Remove-Job $Script:MetricJob
        $Script:MetricJob = $null


        # Update UI (SAFE - we're on UI thread)
        $MetricsCPULabel.Text    = "CPU Usage:        {0:N2} %" -f $Result.CPU
        $MetricsMemoryLabel.Text = "Memory Usage:     {0:N2} %" -f $Result.Memory
        $MetricsDiskLabel.Text   = "C: Disk Activity: {0:N2} %" -f $Result.Disk
        $MetricsUptimeLabel.Text = "System Uptime:    {0:dd\.hh\:mm\:ss}" -f $Result.Uptime


        # Store history
        $Record = [PSCustomObject]@{

            TimeStamp     = Get-Date
            CPUPercent    = [Math]::Round($Result.CPU,2)
            MemoryPercent = [Math]::Round($Result.Memory,2)
            DiskPercent   = [Math]::Round($Result.Disk,2)
            Uptime        = $Result.Uptime

        }


        $Global:MetricHistory += $Record


        # Optional: Limit history size

        if ($Global:MetricHistory.Count -gt 500) {

            $Global:MetricHistory = $Global:MetricHistory[-500..-1]

        }


        $Script:JobRunning = $false

    }

})


# Start timers

$Timer.Start()

$ResultTimer.Start()


# Show form

$Form.ShowDialog() | Out-Null







