try { [System.IO.File]::WriteAllLines($null, @('a')) } finally { Write-Host "FINALLY-RAN" }
Write-Host "AFTER-STATEMENT"
