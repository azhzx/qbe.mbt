#Requires -Version 5.1
<#
.SYNOPSIS
    qbe.mbt installer / bootstrap for Windows (PowerShell).

.DESCRIPTION
    Interactive, rustup-style installer: choose the MoonBit compiler (PATH,
    install, or a custom path), build the qbe binary, and optionally add it to
    your user PATH.

.EXAMPLE
    ./scripts/bootstrap.ps1

.EXAMPLE
    ./scripts/bootstrap.ps1 -SkipInstall -NoPath
#>
[CmdletBinding()]
param(
    [string]$Moon = '',
    [switch]$InstallMoon,
    [switch]$SkipInstall,
    [string]$BinDir = '',
    [switch]$NoPath,
    [switch]$WithReference,
    [ValidateSet('native', 'wasm')]
    [string]$Target = 'native',
    [string]$MoonInstallerUrl = 'https://cli.moonbitlang.cn/install/powershell.ps1',
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------- output
function Write-Step($n, $text) { Write-Host ''; Write-Host "[$n] $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host 'ok  ' -ForegroundColor Green -NoNewline; Write-Host " $text" }
function Write-Info($text) { Write-Host "    $text" -ForegroundColor DarkGray }
function Write-WarnLine($text) { Write-Host "!!  $text" -ForegroundColor Yellow }
function Die($text) { Write-Host "xx  $text" -ForegroundColor Red; exit 1 }

function Show-Banner {
    Write-Host ''
    Write-Host '  +--------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |  qbe.mbt - QBE reimplemented in MoonBit    |' -ForegroundColor Cyan
    Write-Host '  +--------------------------------------------+' -ForegroundColor Cyan
    Write-Host ''
}

function Show-Usage {
    Write-Host @'
Usage: ./scripts/bootstrap.ps1 [options]

  -Moon PATH          Use the MoonBit compiler at PATH.
  -InstallMoon        Install the MoonBit compiler.
  -SkipInstall        Never install the MoonBit compiler.
  -BinDir DIR         Where to install qbe.exe (default: %USERPROFILE%\.qbe\bin).
  -NoPath             Do not offer to add qbe to PATH.
  -WithReference      Also init and build vendor/qbe (differential reference).
  -Target native|wasm Build target (default: native).
  -Yes                Assume "yes"; never prompt.
  -Help               Show this help.
'@
}

if ($Help) { Show-Usage; exit 0 }

# ------------------------------------------------------------------ helpers
function Read-Yes($question, $default = $true) {
    if ($Yes) { return $default }
    $hint = if ($default) { 'Y/n' } else { 'y/N' }
    $ans = Read-Host "$question [$hint]"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    return ($ans -match '^(?i)y(es)?$')
}

function Find-Moon {
    $cmd = Get-Command moon -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Install-Moon {
    Write-Info 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -ErrorAction SilentlyContinue

    # .cn is primary; .com is a fallback where .cn is unreachable.
    $urls = @($MoonInstallerUrl)
    if ($MoonInstallerUrl -notmatch 'moonbitlang\.com') {
        $urls += 'https://cli.moonbitlang.com/install/powershell.ps1'
    }
    $ok = $false
    foreach ($u in $urls) {
        Write-Info "irm $u | iex"
        try {
            $scriptText = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri $u).Content
            Invoke-Expression $scriptText
            $ok = $true
            break
        } catch {
            Write-WarnLine "installer from $u failed: $($_.Exception.Message)"
        }
    }
    if (-not $ok) { Die 'MoonBit installation failed from all mirrors' }

    $installed = Find-Moon
    if (-not $installed) {
        Die "MoonBit was installed but 'moon' is not on PATH yet; open a new terminal and retry"
    }
    return $installed
}

function Use-CustomMoon {
    $p = Read-Host '  Path to the moon executable'
    if ([string]::IsNullOrWhiteSpace($p)) { Die 'no path given' }
    if (-not (Test-Path $p)) { Die "'$p' does not exist" }
    & $p version *> $null
    if ($LASTEXITCODE -ne 0) { Die "'$p' does not look like the MoonBit compiler" }
    return $p
}

function Select-Moon {
    $found = Find-Moon
    Write-Host 'How should we get the MoonBit compiler?'
    if ($found) {
        Write-Host '  1)  Use the moon on PATH      ' -NoNewline
        Write-Host "($found)" -ForegroundColor DarkGray
    } else {
        Write-Host '  1)  Use the moon on PATH      ' -ForegroundColor DarkGray -NoNewline
        Write-Host '(not found)' -ForegroundColor DarkGray
    }
    Write-Host '  2)  Install MoonBit           ' -NoNewline
    Write-Host '(installer script)' -ForegroundColor DarkGray
    Write-Host '  3)  Use a custom moon path'

    $def = if ($found) { '1' } else { '2' }
    if ($Yes) {
        Write-Host "  Choose [$def]: $def"
        $choice = $def
    } else {
        $choice = Read-Host "  Choose [$def]"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $def }
    }
    switch ($choice) {
        '1' {
            if (-not $found) { Die 'no moon on PATH; choose 2 or 3' }
            return $found
        }
        '2' { return Install-Moon }
        '3' { return Use-CustomMoon }
        default { Die "invalid choice: $choice" }
    }
}

function Find-Binary {
    $cands = @(
        (Join-Path '_build' 'native\debug\build\cmd\main\main.exe'),
        (Join-Path '_build' 'native\release\build\cmd\main\main.exe'),
        (Join-Path 'target' 'native\debug\build\cmd\main\main.exe')
    )
    foreach ($c in $cands) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    $hit = Get-ChildItem -Path '_build', 'target' -Recurse -Filter 'main.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'cmd[\\/]main' } |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Install-QbeToPath($exe) {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $dest = Join-Path $BinDir 'qbe.exe'
    Copy-Item -Path $exe -Destination $dest -Force
    Write-Ok "installed $dest"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if (-not [string]::IsNullOrEmpty($userPath)) { $entries = $userPath -split ';' }
    if ($entries -contains $BinDir) {
        Write-Ok "$BinDir is already on your user PATH"
    } else {
        $newPath = if ([string]::IsNullOrEmpty($userPath)) { $BinDir } else { "$userPath;$BinDir" }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Ok "added $BinDir to your user PATH"
    }
    if ($env:Path -notlike "*$BinDir*") { $env:Path = "$env:Path;$BinDir" }
    Write-Host ''
    Write-Host 'Restart your terminal to use qbe.' -ForegroundColor DarkGray
}

# --------------------------------------------------------------------- main
if ([string]::IsNullOrEmpty($BinDir)) {
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    if ([string]::IsNullOrEmpty($homeDir)) { $homeDir = '.' }
    $BinDir = Join-Path $homeDir '.qbe\bin'
}

Show-Banner

Write-Step '1/3' 'MoonBit compiler'
if ($Moon) {
    if (-not (Test-Path $Moon)) { Die "'$Moon' does not exist" }
    $moonCmd = $Moon
    Write-Ok "using $moonCmd"
} elseif ($InstallMoon) {
    $moonCmd = Install-Moon
    Write-Ok "using $moonCmd"
} elseif ($SkipInstall) {
    $moonCmd = Find-Moon
    if (-not $moonCmd) { Die 'no moon on PATH (and -SkipInstall was given)' }
    Write-Ok "using $moonCmd"
} else {
    $moonCmd = Select-Moon
    Write-Ok "using $moonCmd"
}

Write-Step '2/3' 'Building qbe'
Write-Info "$moonCmd build --target $Target"
& $moonCmd build --target $Target
$qbeBin = $null
if ($LASTEXITCODE -ne 0) {
    if ($Target -eq 'native') {
        Write-WarnLine 'native build failed'
        Write-Info 'the native CLI uses POSIX mmap/dlfcn and currently targets macOS/Linux;'
        Write-Info 'falling back to the default target so the project still builds'
        & $moonCmd build
        if ($LASTEXITCODE -ne 0) { Die 'moon build failed' }
        Write-Ok 'built the default target'
    } else {
        Die 'moon build failed'
    }
} else {
    $qbeBin = Find-Binary
    if (-not $qbeBin) { Die 'could not find the built binary under _build\native' }
    & $qbeBin --help *> $null
    if ($LASTEXITCODE -ne 0) { Write-WarnLine 'the built binary did not respond to --help' }
    Write-Ok "built $qbeBin"
}

if ($WithReference) {
    Write-Info 'initializing and building vendor/qbe (reference)'
    & git submodule update --init --recursive vendor/qbe
    if ($LASTEXITCODE -ne 0) { Die 'could not init vendor/qbe' }
    Push-Location vendor/qbe
    try {
        & make
        if ($LASTEXITCODE -ne 0) { Die 'vendor/qbe build failed' }
    } finally {
        Pop-Location
    }
    Write-Ok 'vendor/qbe built'
}

Write-Step '3/3' 'Shell integration'
if ($NoPath) {
    if ($qbeBin) { Write-Info "skipped (-NoPath); the binary is at $qbeBin" }
    else { Write-Info 'skipped (-NoPath)' }
} elseif (-not $qbeBin) {
    Write-Info 'no native qbe.exe was produced, so there is nothing to add to PATH'
    Write-Info 'the cross-platform backends still build with: moon build'
} elseif (Read-Yes "Add qbe to your PATH (install to $BinDir)" $true) {
    Install-QbeToPath $qbeBin
} else {
    Write-Info "skipped; the binary is at $qbeBin"
}

Write-Host ''
Write-Host 'qbe.mbt is ready.' -ForegroundColor Green
