# G-package helper: byte-level multi-pattern scan (ASCII + UTF-16LE), read-only.
param(
  [Parameter(Mandatory=$true)][string[]]$Patterns,
  [Parameter(Mandatory=$true)][string[]]$Files,
  [int]$MaxHitsPerFilePattern = 5
)
function Find-All([byte[]]$bytes, [byte[]]$pat) {
  $hits = New-Object System.Collections.Generic.List[int]
  $n = $bytes.Length; $m = $pat.Length
  if ($m -eq 0 -or $n -lt $m) { return $hits }
  $first = $pat[0]
  for ($i = 0; $i -le $n - $m; $i++) {
    if ($bytes[$i] -eq $first) {
      $ok = $true
      for ($j = 1; $j -lt $m; $j++) {
        if ($bytes[$i + $j] -ne $pat[$j]) { $ok = $false; break }
      }
      if ($ok) { $hits.Add($i); if ($hits.Count -ge 1000) { break } }
    }
  }
  return $hits
}
foreach ($f in $Files) {
  if (-not (Test-Path -LiteralPath $f)) { Write-Output "MISSING`t$f"; continue }
  $fi = Get-Item -LiteralPath $f
  try { $bytes = [System.IO.File]::ReadAllBytes($f) } catch { Write-Output "READFAIL`t$f`t$($_.Exception.Message)"; continue }
  foreach ($p in $Patterns) {
    $pats = @{
      ascii   = [System.Text.Encoding]::ASCII.GetBytes($p)
      utf16le = [System.Text.Encoding]::Unicode.GetBytes($p)
      utf16be = [System.Text.Encoding]::BigEndianUnicode.GetBytes($p)
    }
    foreach ($enc in @('ascii','utf16le','utf16be')) {
      $hits = Find-All $bytes $pats[$enc]
      $count = $hits.Count
      if ($count -gt 0) {
        $shown = ($hits | Select-Object -First $MaxHitsPerFilePattern) -join ','
        Write-Output ("HIT`t{0}`t{1}`t{2}`tcount={3}`toffsets={4}" -f $f, $p, $enc, $count, $shown)
      } else {
        Write-Output ("NOHIT`t{0}`t{1}`t{2}" -f $f, $p, $enc)
      }
    }
  }
}
