$FolderPath = "C:\Docs"
$ServerInstance = "localhost\SQLEXPRESS"
$Database = "AI"

# Establish a secure connection using ADO.NET
$ConnectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"
$Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)

try {
    $Connection.Open()
    
    # Prepare the parameterized SQL command once
    $Query = "INSERT INTO Documents (FileName, SectionTitle, Content) VALUES (@FileName, @SectionTitle, @Content)"
    $Command = $Connection.CreateCommand()
    $Command.CommandText = $Query

    $pFileName = $Command.Parameters.Add("@FileName", [System.Data.SqlDbType]::VarChar, 255)
    $pSectionTitle = $Command.Parameters.Add("@SectionTitle", [System.Data.SqlDbType]::VarChar, 100)
    $pContent = $Command.Parameters.Add("@Content", [System.Data.SqlDbType]::VarChar, -1) # -1 represents VARCHAR(MAX)

    # Load all .txt files
    $Files = Get-ChildItem -Path $FolderPath -Filter *.txt

    foreach ($File in $Files) {
        $Content = Get-Content -Path $File.FullName -Encoding UTF8
        $FileName = $File.Name

        # Skip empty files
        if ([string]::IsNullOrWhiteSpace($Content)) { continue }

        # Split content by double line breaks (paragraphs)
        $Sections = $Content -Split "(\r?\n){2,}" | Where-Object { $_.Trim() -ne "" }

        $I = 1
        foreach ($Section in $Sections) {
            $SectionTitle = "Section $I"

            # Set parameter values (Safe from SQL injection and syntax errors)
            $pFileName.Value = $FileName
            $pSectionTitle.Value = $SectionTitle
            $pContent.Value = $Section.Trim()

            Write-Host "Inserindo: $FileName - Section $I..." -ForegroundColor Cyan
            [void]$Command.ExecuteNonQuery()

            $I++
        }
    }

    Write-Host "Processamento concluído com sucesso!" -ForegroundColor Green
}
catch {
    Write-Error "Ocorreu um erro durante o processamento: $_"
}
finally {
    if ($Connection.State -eq 'Open') {
        $Connection.Close()
    }
}