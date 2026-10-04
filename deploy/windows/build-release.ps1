<#
.SYNOPSIS
  Arma el paquete de instalacion (release\warique-<version>.zip) en la maquina de desarrollo.
.DESCRIPTION
  Requiere Node.js 22, npm y Flutter en el PATH (Windows, Linux o macOS; PowerShell 5.1 o 7).
  El paquete incluye node_modules de produccion y el motor de Prisma para Windows, asi que la
  PC del local no necesita internet ni herramientas de compilacion para instalarlo.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File deploy\windows\build-release.ps1 -WithApk
#>
[CmdletBinding()]
param(
    # Tambien compila el APK de Android y lo publica en http://<PC>:3000/descargas/warique.apk
    [switch]$WithApk,
    [switch]$SkipTests,
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

# WinSW 2.12.0 (MIT, github.com/winsw/winsw). Pinned hash: a tampered download aborts the build.
$WinSwUrl = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
$WinSwSha256 = '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutDir) { $OutDir = Join-Path $repo 'release' }
$backend = Join-Path $repo 'backend'
$app = Join-Path $repo 'app'

function Invoke-Checked([string]$WorkingDirectory, [string]$Command, [string[]]$Arguments) {
    Push-Location $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Command $($Arguments -join ' ') termino con codigo $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Copy-Directory([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    Copy-Item -Path (Join-Path $From '*') -Destination $To -Recurse -Force
}

$version = (Get-Content -LiteralPath (Join-Path $backend 'package.json') -Raw | ConvertFrom-Json).version
$name = "warique-$version"
$stage = Join-Path $OutDir $name
$zipFile = Join-Path $OutDir "$name.zip"
Write-Step "Armando $name"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zipFile) { Remove-Item -LiteralPath $zipFile -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Step 'Backend: dependencias, cliente Prisma (incluye motor Windows), pruebas y compilacion'
Invoke-Checked $backend 'npm' @('ci')
Invoke-Checked $backend 'npx' @('prisma', 'generate')
if (-not $SkipTests) { Invoke-Checked $backend 'npm' @('test') }
Invoke-Checked $backend 'npm' @('run', 'build')

Write-Step 'App Flutter: pruebas y compilacion web (sin CDN: funciona sin internet)'
Invoke-Checked $app 'flutter' @('pub', 'get')
if (-not $SkipTests) { Invoke-Checked $app 'flutter' @('test') }
Invoke-Checked $app 'flutter' @('build', 'web', '--release', '--no-web-resources-cdn')
if ($WithApk) {
    if (-not (Test-Path -LiteralPath (Join-Path $app 'android\key.properties'))) {
        Write-Warn 'Sin android\key.properties: el APK se firma con la clave de depuracion (ver README).'
    }
    Invoke-Checked $app 'flutter' @('build', 'apk', '--release')
}

Write-Step 'Ensamblando el paquete'
$stageApp = Join-Path $stage 'app'
Copy-Directory (Join-Path $backend 'dist') (Join-Path $stageApp 'dist')
# Explicit loop: on Windows PowerShell 5.1, piping Get-ChildItem -Include results into Remove-Item
# throws NullReferenceException
$testFiles = @(Get-ChildItem -LiteralPath (Join-Path $stageApp 'dist') -Recurse -File |
        Where-Object { $_.Name -like '*.spec.js' -or $_.Name -like '*.spec.d.ts' -or $_.Name -like '*.tsbuildinfo' })
foreach ($testFile in $testFiles) { Remove-Item -LiteralPath $testFile.FullName -Force }
foreach ($file in @('package.json', 'package-lock.json')) {
    Copy-Item -LiteralPath (Join-Path $backend $file) -Destination $stageApp
}
New-Item -ItemType Directory -Force -Path (Join-Path $stageApp 'prisma') | Out-Null
Copy-Item -LiteralPath (Join-Path $backend 'prisma\schema.prisma') -Destination (Join-Path $stageApp 'prisma')
Copy-Directory (Join-Path $app 'build\web') (Join-Path $stageApp 'public')
if ($WithApk) {
    $downloads = Join-Path $stageApp 'public\descargas'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    Copy-Item -LiteralPath (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') -Destination (Join-Path $downloads 'warique.apk')
}

# Production dependencies only. --omit=optional: @prisma/client declares the Prisma CLI and
# TypeScript as optional peers (~110 MB, "devOptional" in the lockfile) never used at runtime; the
# other optional packages belong to dev tools. --ignore-scripts: no install scripts run; the
# Prisma client generated above (with the Windows engine) is copied instead of regenerated
Invoke-Checked $stageApp 'npm' @('ci', '--omit=dev', '--omit=optional', '--ignore-scripts', '--no-audit', '--no-fund')
Copy-Directory (Join-Path $backend 'node_modules\.prisma') (Join-Path $stageApp 'node_modules\.prisma')
if (-not (Test-Path -LiteralPath (Join-Path $stageApp 'node_modules\.prisma\client\query_engine-windows.dll.node'))) {
    throw 'Falta el motor de Prisma para Windows (binaryTargets en schema.prisma).'
}

Copy-Directory (Join-Path $repo 'database') (Join-Path $stage 'database')
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'scripts'), (Join-Path $stage 'service') | Out-Null
foreach ($script in @('common.ps1', 'install.ps1', 'update.ps1', 'backup.ps1', 'restore.ps1', 'status.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $stage 'scripts')
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GUIA-INSTALACION.md') -Destination $stage

$cacheDir = Join-Path $OutDir '.cache'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$winSw = Join-Path $cacheDir 'WinSW-x64-2.12.0.exe'
if (-not (Test-Path -LiteralPath $winSw)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $WinSwUrl -OutFile $winSw -UseBasicParsing
}
if ((Get-FileHash -LiteralPath $winSw -Algorithm SHA256).Hash -ne $WinSwSha256) {
    Remove-Item -LiteralPath $winSw -Force
    throw 'El SHA256 de WinSW no coincide: descarga alterada o incompleta.'
}
Copy-Item -LiteralPath $winSw -Destination (Join-Path $stage 'service\WinSW-x64.exe')
Write-Utf8File (Join-Path $stage 'VERSION') $version

# ZipFile instead of Compress-Archive: Compress-Archive skips dot-folders such as node_modules\.prisma
# on Linux/macOS, which would ship a package without the Prisma client
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipFile, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash
Write-Utf8File "$zipFile.sha256" "$hash  $name.zip`n"
$sizeMb = [math]::Round((Get-Item -LiteralPath $zipFile).Length / 1MB, 1)
Write-Host "`nPaquete listo: $zipFile ($sizeMb MB)`nSHA256: $hash" -ForegroundColor Green
