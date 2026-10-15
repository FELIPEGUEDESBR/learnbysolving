#Install-Module -Name PSWritePDF -Scope CurrentUser



$FolderPath = "C:\Docs"
$ServerInstance = "localhost\SQLEXPRESS"
$Database = "AI"



# Estabelecer conexão segura com o SQL Server
$ConnectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"
$Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)

try {
    $Connection.Open()

    # Preparar o comando SQL parametrizado
    $Query = @"
INSERT INTO Documents (FileName, SectionTitle, Content)
VALUES (@FileName, @SectionTitle, @Content)
"@

    $Command = $Connection.CreateCommand()
    $Command.CommandText = $Query

    $pFileName = $Command.Parameters.Add(
        "@FileName",
        [System.Data.SqlDbType]::VarChar,
        255
    )

    $pSectionTitle = $Command.Parameters.Add(
        "@SectionTitle",
        [System.Data.SqlDbType]::VarChar,
        100
    )

    $pContent = $Command.Parameters.Add(
        "@Content",
        [System.Data.SqlDbType]::VarChar,
        -1
    )

    # Obter todos os ficheiros PDF da pasta
    $Files = Get-ChildItem -Path $FolderPath -Filter "*.pdf" -File

    foreach ($File in $Files) {
        $FileName = $File.Name

        Write-Host "Processando PDF: $FileName..." -ForegroundColor Yellow

        try {
            # Extrair o texto do PDF com o PSWritePDF
            $Pages = @(
                Convert-PDFToText `
                    -FilePath $File.FullName `
                    -ExtractionStrategy SimpleTextExtractionStrategy `
                    -ErrorAction Stop
            )

            # Combinar o texto de todas as páginas
            $Content = (
                $Pages | ForEach-Object {
                    if ($_ -is [string]) {
                        $_
                    }
                    elseif ($_.PSObject.Properties["Text"]) {
                        $_.Text
                    }
                    else {
                        $_ | Out-String
                    }
                }
            ) -join "`r`n`r`n"

            # Ignorar PDFs sem texto extraível
            if ([string]::IsNullOrWhiteSpace($Content)) {
                Write-Host "PDF vazio ou sem texto extraível: $FileName" `
                    -ForegroundColor DarkYellow
                continue
            }

            # Dividir o conteúdo em secções por parágrafos
            $Sections = @(
                $Content -Split '(?:\r?\n\s*){2,}' |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            $I = 1

            foreach ($Section in $Sections) {
                $SectionTitle = "Section $I"
                $SectionContent = $Section.Trim()

                # Definir os parâmetros SQL
                $pFileName.Value = $FileName
                $pSectionTitle.Value = $SectionTitle
                $pContent.Value = $SectionContent

                Write-Host "  -> Inserindo: $FileName - $SectionTitle..." `
                    -ForegroundColor Cyan

                [void]$Command.ExecuteNonQuery()

                $I++
            }

            Write-Host "PDF processado: $FileName ($($Sections.Count) secções)" `
                -ForegroundColor Green
        }
        catch {
            Write-Warning "Erro ao processar '$FileName': $($_.Exception.Message)"
            continue
        }
    }

    Write-Host "Processamento concluído!" -ForegroundColor Green
}
catch {
    Write-Error "Ocorreu um erro durante o processamento: $($_.Exception.Message)"
}
finally {
    # Libertar recursos
    if ($Command) {
        $Command.Dispose()
    }

    if ($Connection.State -eq [System.Data.ConnectionState]::Open) {
        $Connection.Close()
    }

    $Connection.Dispose()
}