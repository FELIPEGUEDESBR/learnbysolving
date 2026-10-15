# Define the prompt
$prompt = "What is the capital of France?"

# Set up the HTTP POST request
$body = @{
    model  = "llama3"
    prompt = $prompt
    stream = $False
} | ConvertTo-Json -Depth 2

# Send the request to the Ollama server
$response = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" `
                              -Method Post `
                              -Body $body `
                              -ContentType "application/json"

# Display the result
$response.response