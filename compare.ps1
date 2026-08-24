$ErrorActionPreference = 'Continue'
$mineExe = 'e:\qbe.mbt\_build\native\debug\build\cmd\main\main.exe'
$refExe = 'e:\qbe.mbt\qbe-master\obj_qbe.exe'
$qbeArgs = $args

# Build the native MoonBit executable first.
Set-Location e:\qbe.mbt
moon build --target native | Out-Null

# Run MoonBit version - capture stderr (debug output channel, matching QBE)
& $mineExe @qbeArgs 1> _null.txt 2> _mine.txt

# Run C reference - capture stderr (QBE writes debug to stderr)
& $refExe @qbeArgs 1> _null.txt 2> _ref.txt

Write-Host "=== MINE (first 5 lines) ==="
Get-Content _mine.txt | Select-Object -First 5
Write-Host "=== REF (first 5 lines) ==="
Get-Content _ref.txt | Select-Object -First 5
Write-Host "=== DIFF ==="
$diff = Compare-Object (Get-Content _mine.txt) (Get-Content _ref.txt)
if ($diff) {
    $diff | Format-Table -AutoSize
    Write-Host "Total differences: $($diff.Count)"
} else {
    Write-Host "IDENTICAL!"
}
