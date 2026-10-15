Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Create Form ---
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Stable Diffusion GUI"
$Form.Size = New-Object System.Drawing.Size(1000, 1000)
$Form.Font = New-Object System.Drawing.Font("Arial", 14)

# --- Model Selection ---
$ModelLabel = New-Object System.Windows.Forms.Label
$ModelLabel.Text = "Model:"
$ModelLabel.Location = New-Object System.Drawing.Point(20, 20)
$ModelLabel.AutoSize = $True
$Form.Controls.Add($ModelLabel) | Out-Null

$ModelComboBox = New-Object System.Windows.Forms.ComboBox
$ModelComboBox.Location = New-Object System.Drawing.Point(175, 20)
$ModelComboBox.Size = New-Object System.Drawing.Size(300, 30)
$ModelComboBox.Items.AddRange(@("sd-v1-4","sd-v1-5","sdxl-base"))
$ModelComboBox.SelectedIndex = 0
$Form.Controls.Add($ModelComboBox) | Out-Null

# --- Resolution Selection ---
$ResolutionLabel = New-Object System.Windows.Forms.Label
$ResolutionLabel.Text = "Resolution:"
$ResolutionLabel.Location = New-Object System.Drawing.Point(20,70)
$ResolutionLabel.AutoSize = $True
$Form.Controls.Add($ResolutionLabel) | Out-Null

$ResolutionComboBox = New-Object System.Windows.Forms.ComboBox
$ResolutionComboBox.Location = New-Object System.Drawing.Point(175,70)
$ResolutionComboBox.Size = New-Object System.Drawing.Size(300,30)
$ResolutionComboBox.Items.AddRange(@("256x256","512x512","768x768","1024x1024"))
$ResolutionComboBox.SelectedIndex = 1
$Form.Controls.Add($ResolutionComboBox) | Out-Null

# --- CFG Scale TrackBar ---
$CFGLabel = New-Object System.Windows.Forms.Label
$CFGLabel.Text = "CFG Scale:"
$CFGLabel.Location = New-Object System.Drawing.Point(20,120)
$CFGLabel.AutoSize = $True
$Form.Controls.Add($CFGLabel) | Out-Null

$CFgTrackbar = New-Object System.Windows.Forms.TrackBar
$CFgTrackbar.Location = New-Object System.Drawing.Point(175,120)
$CFgTrackbar.Size = New-Object System.Drawing.Size(300,30)
$CFgTrackbar.Minimum = 1
$CFgTrackbar.Maximum = 20
$CFgTrackbar.Value = 7
$CFgTrackbar.TickFrequency = 1
$Form.Controls.Add($CFgTrackbar) | Out-Null

# --- Steps TrackBar ---
$StepsLabel = New-Object System.Windows.Forms.Label
$StepsLabel.Text = "Steps:"
$StepsLabel.Location = New-Object System.Drawing.Point(20,170)
$StepsLabel.AutoSize = $True
$Form.Controls.Add($StepsLabel) | Out-Null

$StepsTrackbar = New-Object System.Windows.Forms.TrackBar
$StepsTrackbar.Location = New-Object System.Drawing.Point(175,170)
$StepsTrackbar.Size = New-Object System.Drawing.Size(300,30)
$StepsTrackbar.Minimum = 1
$StepsTrackbar.Maximum = 100
$StepsTrackbar.Value = 30
$StepsTrackbar.TickFrequency = 5
$Form.Controls.Add($StepsTrackbar) | Out-Null

# --- Prompt TextBox ---
$PromptLabel = New-Object System.Windows.Forms.Label
$PromptLabel.Text = "Prompt:"
$PromptLabel.Location = New-Object System.Drawing.Point(20,220)
$PromptLabel.AutoSize = $True
$Form.Controls.Add($PromptLabel) | Out-Null

$PromptTextBox = New-Object System.Windows.Forms.RichTextBox
$PromptTextBox.Location = New-Object System.Drawing.Point(175,220)
$PromptTextBox.Size = New-Object System.Drawing.Size(500,300)
$Form.Controls.Add($PromptTextBox) | Out-Null

# --- Submit Button ---
$SubmitButton = New-Object System.Windows.Forms.Button
$SubmitButton.Text = "Generate Image"
$SubmitButton.Location = New-Object System.Drawing.Point(150,600)
$SubmitButton.Size = New-Object System.Drawing.Size(200,40)
$Form.Controls.Add($SubmitButton) | Out-Null

# --- PictureBox to Display Image ---
$PictureBoxImage = New-Object System.Windows.Forms.PictureBox
$PictureBoxImage.Location = New-Object System.Drawing.Point(700,20)
$PictureBoxImage.Size = New-Object System.Drawing.Size(1200,1000)
$PictureBoxImage.SizeMode = "Zoom"
$Form.Controls.Add($PictureBoxImage) | Out-Null

# --- Submit Button Click Event ---
$SubmitButton.Add_Click({
    Try {
        $Prompt = $PromptTextBox.Text
        $Model = $ModelComboBox.SelectedItem
        $Resolution = $ResolutionComboBox.SelectedItem.Split("x")
        $Width = [int]$Resolution[0]
        $Height = [int]$Resolution[1]
        $CFGScale = $CFgTrackbar.Value
        $Steps = $StepsTrackbar.Value

    $Body = @{
        prompt = $Prompt
        width = $Width
        height = $Height
        guidance_scale = $CFGScale
        num_inference_steps = $Steps
        model = $Model
    } | ConvertTo-Json

# --- REST API Call (update the URL to your local server) ---
$TempFile = "C:\Temp\generated15.png"

Invoke-RestMethod `
    -Uri "http://localhost:7860/txt2img" `
    -Method Post `
    -Body $Body `
    -ContentType "application/json" `
    -OutFile $TempFile

$PictureBoxImage.Image = [System.Drawing.Image]::FromFile($TempFile)

    }
    Catch {
        [System.Windows.Forms.MessageBox]::Show("Error generating image:`n$($_.Exception.Message)")
    }
})

# --- Show Form ---
$Form.ShowDialog() | Out-Null