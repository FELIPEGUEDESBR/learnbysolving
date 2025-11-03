# ============================================
# ChatGPT PowerShell Client (versão interativa)
# ============================================

# Pergunta pela API Key (ou usa a variável do ambiente)
if (-not $env:OPENAI_API_KEY) {
    $apiKey = Read-Host "Digite sua API Key da OpenAI (sk-...)"
} else {
    $useEnv = Read-Host "Detectei uma API Key no ambiente. Deseja usá-la? (S/N)"
    if ($useEnv -match "^[sS]") {
        $apiKey = $env:OPENAI_API_KEY
    } else {
        $apiKey = Read-Host "Digite sua API Key da OpenAI (sk-...)"
    }
}

# Pergunta o conteúdo inicial (prompt)
$userPrompt = Read-Host "Digite o conteúdo da sua pergunta (prompt inicial)"

# Cabeçalhos da requisição
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
}

# Inicializa contexto da conversa
$messages = @(
    @{
        role    = "system"
        content = "Você é um assistente técnico que responde com clareza e objetividade."
    },
    @{
        role    = "user"
        content = $userPrompt
    }
)

# Monta o corpo JSON
$body = @{
    model    = "gpt-4o-mini"  # Pode alterar para "gpt-4o" se quiser mais qualidade
    messages = $messages
} | ConvertTo-Json -Depth 5

# Faz a chamada à API
$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Headers $headers -Body $body -Method Post

# Exibe a resposta do modelo
Write-Host "`nChatGPT:" -ForegroundColor Cyan
$response.choices.message.content | Write-Host -ForegroundColor Yellow

# Loop opcional — continuar a conversa
while ($true) {
    $userInput = Read-Host "`nVocê (digite 'sair' para encerrar)"
    if ($userInput -eq "sair") { break }

    $messages += @{ role = "user"; content = $userInput }

    $body = @{
        model    = "gpt-4o-mini"
        messages = $messages
    } | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Headers $headers -Body $body -Method Post
    $reply = $response.choices.message.content

    Write-Host "`nChatGPT:" -ForegroundColor Cyan
    Write-Host $reply -ForegroundColor Yellow

    $messages += @{ role = "assistant"; content = $reply }
}