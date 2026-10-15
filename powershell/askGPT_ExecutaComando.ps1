Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. ./NoScale.ps1

############# Invoke-Ollama Function #############

Function Invoke-Ollama {
    param ($Task)

$Prompt = @"
You are a PowerShell assistant.
Respond with ONLY a single-line PowerShell command.
Do NOT include explanations, comments, markdown, or code blocks.
Do NOT use semicolons or line breaks.
Do NOT use tickmarks to indicate where the code begins.
Task: $Task
"@

    $body = @{
        Model  = "llama3"
        Prompt = $Prompt
        Stream = $False
    } | ConvertTo-Json

    Try {
        $Response = Invoke-RestMethod `
            -Uri "http://localhost:11434/api/generate" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body

        Return $Response.Response.Trim()
    }
    Catch {
        Return "ERROR: Unable to contact Ollama"
    }
}

############# Investigate-Command Function #############

Function Investigate-Command{

    param ($Cmd)

$Prompt = @"
You are a PowerShell assistant
Please provide a detailed explanation of what the following command does and how it works.
Here is the command: $Cmd
"@

    $body = @{
        Model  = "Llama3"
        Prompt = $Prompt
        Stream = $False
    } | ConvertTo-Json

    Try {
        $Response = Invoke-RestMethod `
            -Uri "http://localhost:11434/api/generate" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body

        Return $Response.Response.Trim()
    }
    Catch {
        Return "ERROR: Unable to contact Ollama"
    }
}

######################## Create GUI Objects ########################

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PowerShell Command Generator"
$Form.Size = New-Object System.Drawing.Size(1920, 1080)
$Form.StartPosition = "CenterScreen"

$Form2 = New-Object System.Windows.Forms.Form
$Form2.Text = "Investigate Command Form"
$Form2.Size = New-Object System.Drawing.Size(1920, 1080)
$Form2.StartPosition = "CenterScreen"

$PageLabel = New-Object System.Windows.Forms.Label
$PageLabel.Text = "Describe the Task That You Want to Perform:"
$PageLabel.Font = New-Object System.Drawing.Font("Arial", 24, [System.Drawing.FontStyle]::Bold)
$PageLabel.Location = '20,20'
$PageLabel.AutoSize = $True

$PageLabel2 = New-Object System.Windows.Forms.Label
$PageLabel2.Text = "Investigate Command"
$PageLabel2.Font = New-Object System.Drawing.Font("Arial", 24, [System.Drawing.FontStyle]::Bold)
$PageLabel2.Location = '20,20'
$PageLabel2.AutoSize = $True

$TaskLabel = New-Object System.Windows.Forms.Label
$TaskLabel.Text = "Describe the Task That You Want to Perform:"
$TaskLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$TaskLabel.Location = '20,100'
$TaskLabel.AutoSize = $True

$TaskLabel2 = New-Object System.Windows.Forms.Label
$TaskLabel2.Text = "Outputs are Limited to a Single Command"
$TaskLabel2.Font = New-Object System.Drawing.Font("Arial", 14)
$TaskLabel2.Location = '20,150'
$TaskLabel2.AutoSize = $True

$TaskBox = New-Object System.Windows.Forms.TextBox
$TaskBox.Location = '10,200'
$TaskBox.Size = '1850,200'
$TaskBox.Multiline = $true
$TaskBox.Font = New-Object System.Drawing.Font("Arial", 14)

$OutputLabel = New-Object System.Windows.Forms.Label
$OutputLabel.Text = "Generated PowerShell Command:"
$OutputLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$OutputLabel.Location = '20,500'
$OutputLabel.AutoSize = $True

$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Location = '20,550'
$OutputBox.Size = '1850,50'
$OutputBox.ReadOnly = $True
$OutputBox.Font = New-Object System.Drawing.Font("Arial", 14)

$ExplanationBox = New-Object System.Windows.Forms.RichTextBox
$ExplanationBox.Location = '10,100'
$ExplanationBox.Size = '1850,600'
$ExplanationBox.Font = New-Object System.Drawing.Font("Arial", 14)
$ExplanationBox.Multiline = $True

$GenerateButton = New-Object System.Windows.Forms.Button
$GenerateButton.Text = "Generate"
$GenerateButton.Location = '20,650'
$GenerateButton.Size = '150,50'
$GenerateButton.Font = New-Object System.Drawing.Font("Arial", 14)

$RunButton = New-Object System.Windows.Forms.Button
$RunButton.Text = "Run"
$RunButton.Location = '200,650'
$RunButton.Size = '150,50'
$RunButton.Font = New-Object System.Drawing.Font("Arial", 14)

$ClipboardButton = New-Object System.Windows.Forms.Button
$ClipboardButton.Text = "Clipboard"
$ClipboardButton.Location = '600,650'
$ClipboardButton.Size = '150,50'
$ClipboardButton.Font = New-Object System.Drawing.Font("Arial", 14)

$InvestigateButton = New-Object System.Windows.Forms.Button
$InvestigateButton.Text = "Investigate"
$InvestigateButton.Location = '800,650'
$InvestigateButton.Size = '175,50'
$InvestigateButton.Font = New-Object System.Drawing.Font("Arial", 14)

$ExitButton = New-Object System.Windows.Forms.Button
$ExitButton.Text = "Exit"
$ExitButton.Location = '200,800'
$ExitButton.Size = '150,50'
$ExitButton.Font = New-Object System.Drawing.Font("Arial", 14)

######################## Define Button Click Actions ########################

########### Generate Button ###########

$GenerateButton.Add_Click({
    $OutputBox.Text = Invoke-Ollama -Task $TaskBox.Text
})


########### Run Button ###########
$RunButton.Add_Click({
    $Cmd =$OutputBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($Cmd)) { Return }

    $Confirm = [System.Windows.Forms.MessageBox]::Show(
        "Run this command?`n`n$Cmd",
        "Confirm Execution",
        "YesNo",
        "Warning"
    )

    If ($Confirm -eq "Yes") {
        $BlockedWords = "Remove-", "Format-", "Stop-Computer"

        If ($BlockedWords | Where-Object { $Cmd -match$_ }) {
            [System.Windows.Forms.MessageBox]::Show("Command blocked for safety.")
            Return
        }

        Try {
            Start-Process powershell.exe `
                -ArgumentList "-NoExit", "-Command", $Cmd `
                -WindowStyle Normal
        }
        Catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message)
        }
    }
})

########### Clipboard Button ###########

$ClipboardButton.Add_Click({
    if (-not [string]::IsNullOrEmpty($OutputBox.Text)) {
        [System.Windows.Forms.Clipboard]::SetText($OutputBox.Text)
    }
})

########### Exit Button ###########

$ExitButton.Add_Click({
    $Form2.Close()
})


########### Investigate Button ###########
$InvestigateButton.Add_Click({
$Form2.Controls.Add($PageLabel2) | Out-Null
$Form2.Controls.Add($ExplanationBox) | Out-Null
$Form2.Controls.Add($ExitButton) | Out-Null

$Cmd = $OutputBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Cmd)) { Return }

$ExplanationBox.Text = Investigate-Command -Cmd $Cmd

$Form2.ShowDialog() | Out-Null
})

#################### Add the GUI Objects to the Form ####################

$Form.Controls.Add($PageLabel) | Out-Null
$Form.Controls.Add($TaskLabel) | Out-Null
$Form.Controls.Add($TaskLabel2) | Out-Null
$Form.Controls.Add($TaskBox) | Out-Null
$Form.Controls.Add($OutputLabel) | Out-Null
$Form.Controls.Add($OutputBox) | Out-Null
$Form.Controls.Add($GenerateButton) | Out-Null
$Form.Controls.Add($RunButton) | Out-Null
$Form.Controls.Add($ClipboardButton) | Out-Null
$Form.Controls.Add($InvestigateButton) | Out-Null


$Form.ShowDialog() | Out-Null