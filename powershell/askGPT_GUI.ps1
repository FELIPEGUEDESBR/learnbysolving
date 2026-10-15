# Load Assemblies

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. ./NoScale.ps1

Function Invoke-Ollama {
    param ($SafeUserInput)

$Prompt = @"
You are a helpful assistant.
Input: $SafeUserInput
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

# Create the main form
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "AI Chatbot"
$Form.Size = New-Object System.Drawing.Size(1920,1080)
$Form.StartPosition = 'CenterScreen'
$Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

# Create the input label
$InputLabel = New-Object System.Windows.Forms.Label
$InputLabel.Text = "Text Input"
$InputLabel.Location = New-Object System.Drawing.Point(0,600)
$InputLabel.Size = New-Object System.Drawing.Size(1850,50)
$InputLabel.Font = New-Object System.Drawing.Font("Arial", 14)  # Default font
$InputLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$InputLabel.BackColor = [System.Drawing.Color]::LightBlue
$InputLabel.ForeColor = [System.Drawing.Color]::Black

# Create the Submit Button
$SubmitButton = New-Object System.Windows.Forms.Button
$SubmitButton.Font = New-Object System.Drawing.Font("Arial", 14)
$SubmitButton.Location = New-Object System.Drawing.Point(350,875)
$SubmitButton.Size = New-Object System.Drawing.Size(150,50)
$SubmitButton.Text = "Submit"

# Create the Exit Button
$ExitButton = New-Object System.Windows.Forms.Button
$ExitButton.Font = New-Object System.Drawing.Font("Arial", 14)

$ExitButton.Location = New-Object System.Drawing.Point(550,875)
$ExitButton.Size = New-Object System.Drawing.Size(150,50)
$ExitButton.Text = "Exit"
$ExitButton.Add_Click({
    $Form.Close()
})

# Create the User Input TextBox (Multiline for long text)
$InputBox = New-Object System.Windows.Forms.RichTextBox
$InputBox.Location = New-Object System.Drawing.Point(0,650)
$InputBox.Size = New-Object System.Drawing.Size(1850, 200)
$InputBox.Font = New-Object System.Drawing.Font("Arial", 14)
$InputBox.Multiline = $True
$InputBox.ScrollBars = "Vertical"

# Create the output label
$OutputLabel = New-Object System.Windows.Forms.Label
$OutputLabel.Text = "AI Output"
$OutputLabel.Location = New-Object System.Drawing.Point(0,50)
$OutputLabel.Size = New-Object System.Drawing.Size(1850, 50)
$OutputLabel.Font = New-Object System.Drawing.Font("Arial", 14)
$OutputLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$OutputLabel.BackColor = [System.Drawing.Color]::LightBlue
$OutputLabel.ForeColor = [System.Drawing.Color]::Black

# Create the output (left) RichTextBox
$OutputBox = New-Object System.Windows.Forms.RichTextBox
$OutputBox.Multiline = $True
$OutputBox.Location = New-Object System.Drawing.Point(0,100)
$OutputBox.Size = New-Object System.Drawing.Size(1850,500)
$OutputBox.Font = New-Object System.Drawing.Font("Arial", 14)  # Default font
$OutputBox.BackColor = "#FFFFFFFF"
$OutputBox.ReadOnly = $False
$OutputBox.Multiline = $True
$OutputBox.ScrollBars = "Vertical"
$OutputBox.Text = ""

$Form.Controls.Add($InputLabel) | Out-Null
$Form.Controls.Add($InputBox) | Out-Null
$Form.Controls.Add($OutputLabel) | Out-Null
$Form.Controls.Add($SubmitButton) | Out-Null
$Form.Controls.Add($ExitButton) | Out-Null
$Form.Controls.Add($OutputBox) | Out-Null


#############################################
###                                       ###
###             Submit Button             ###
###                                       ###
#############################################

# Event Handler for Submit Button
$SubmitButton.Add_Click({

$UserInput =$InputBox.Text
if ($UserInput -ne "") {


###   Write the user's query to the output box ############

$OutputBox.SelectionStart =$OutputBox.TextLength
$OutputBox.SelectionLength = 0
$OutputBox.SelectionColor = "#FF0000FF"    #Set the text color to Blue

$OutputBox.SelectionStart =$OutputBox.TextLength
$OutputBox.SelectionLength = 4  # So that I can format the word You and the colon after.
$OutputBox.SelectionFont = New-Object System.Drawing.Font($OutputBox.Font, [System.Drawing.FontStyle]::Bold)
[String]$OutputText = "You: "
$OutputBox.AppendText("`r`n`r`n$OutputText")

$OutputBox.SelectionStart =$OutputBox.TextLength
$OutputBox.SelectionLength = 0

$OutputBox.SelectionFont = New-Object System.Drawing.Font($OutputBox.Font, [System.Drawing.FontStyle]::Regular)
$OutputText =$UserInput
$OutputBox.AppendText("$UserInput`r`n")

##### Clear the input box to make room for the next query ####
$InputBox.Clear()


#### Get rid of any invalid characters ######################

# Append user message
$SafeUserInput = [string]$UserInput -replace '[\u0000-\u001F]', ''


##### Perform the actual query #####

$Response = Invoke-Ollama -SafeUserInput $SafeUserInput


$TrimmedResponse =$Response

## Display the results from the query

$OutputBox.SelectionStart =$OutputBox.TextLength
$OutputBox.SelectionLength = $Model.Length + 1
$OutputBox.SelectionColor = "#FF000000"    

# Set the text color to black
$OutputBox.SelectionFont = New-Object System.Drawing.Font($OutputBox.Font, [System.Drawing.FontStyle]::Bold)
[String]$OutputText = "AI: " + $TrimmedResponse
$OutputBox.AppendText("`r`n$OutputText`r`n`r`n")

}

})

# Show the form

$Form.ShowDialog() | Out-Null
