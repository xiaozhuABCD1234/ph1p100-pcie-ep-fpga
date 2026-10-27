# dbg4.ps1 -- ASCII-only: (a) capture WAL arg messages to UTF-8 files; (b) LF-only minimal no-BOM vs BOM discriminator
$here = $PSScriptRoot
$msgs = @()
try { [System.IO.File]::WriteAllLines($null, @('a')) } catch { $msgs += 'NULL: ' + $_.Exception.Message }
try { [System.IO.File]::WriteAllLines('', @('a')) } catch { $msgs += 'EMPTY: ' + $_.Exception.Message }
try { [System.IO.File]::WriteAllLines(("C:\x" + [char]10 + "y"), @('a')) } catch { $msgs += 'CTRL: ' + $_.Exception.Message }
[System.IO.File]::WriteAllText((Join-Path $here 't5_wal_messages.txt'), ($msgs -join "`n"), (New-Object System.Text.UTF8Encoding($false)))

# LF-only minimal scripts (Chinese built from char codes; ASCII source)
$cn = '# ' + [char]0x4E2D + [char]0x6587 + [char]0x53E5 + [char]0x53F7 + [char]0x3002
$body = $cn + "`n" + '$x = 42' + "`n" + 'if ($null -eq $x) { "X_IS_NULL" } else { "X=$x" }' + "`n"
$noBom = Join-Path $here 't1c_nobom_lf.ps1'
$withBom = Join-Path $here 't1d_bom_lf.ps1'
[System.IO.File]::WriteAllText($noBom, $body, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($withBom, $body, (New-Object System.Text.UTF8Encoding($true)))
$r1 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $noBom 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
$r2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $withBom 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
$cmd = 'chcp 65001 >nul & powershell -NoProfile -ExecutionPolicy Bypass -File "' + $noBom + '"'
$r3 = (cmd /c $cmd 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
$res = @(
  'LF-only noBOM        : [' + $r1 + ']',
  'LF-only withBOM      : [' + $r2 + ']',
  'LF-only noBOM chcp65001: [' + $r3 + ']'
)
[System.IO.File]::WriteAllText((Join-Path $here 't6_lf_discriminator.txt'), ($res -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
$res | ForEach-Object { $_ }
