
rm $env:TEMP\* -r -Force -ErrorAction SilentlyContinue


reg delete HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f


Remove-Item (Get-PSreadlineOption).HistorySavePath


Clear-RecycleBin -Force -ErrorAction SilentlyContinue
