<#
.SYNOPSIS
  Actualiza Warique a la version del paquete donde esta este script.
.DESCRIPTION
  Ejecutar como administrador desde el paquete NUEVO descomprimido:
    powershell -ExecutionPolicy Bypass -File .\scripts\update.ps1
  1. Respaldo de la base de datos (si falla, no actualiza).
  2. Detiene el servicio, guarda la version actual en app.previous y copia la nueva.
  3. Inicia y verifica /api/health. Si no responde, vuelve sola a la version anterior.
  No modifica la base de datos: si una version trae cambios de esquema, vienen en
  database\migrations con instrucciones aparte.
#>
[CmdletBinding()]
param([string]$InstallDir = 'C:\Warique')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$ReleaseDir = Split-Path $PSScriptRoot -Parent
$config = Get-DeployConfig $InstallDir
$appDir = Join-Path $InstallDir 'app'
$previousDir = Join-Path $InstallDir 'app.previous'
$newVersion = (Get-Content -LiteralPath (Join-Path $ReleaseDir 'VERSION') -Raw).Trim()

function Start-AndCheck {
    Start-Service -Name $config.serviceName
    return (Wait-Health ([int]$config.port) 90)
}

function Copy-Tree([string]$From, [string]$To) {
    $process = Start-Process robocopy.exe -ArgumentList (ConvertTo-ArgumentString @(
            $From, $To, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')) -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ge 8) { throw "robocopy fallo con codigo $($process.ExitCode)" }
}

Assert-Administrator
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir 'app\dist\main.js'))) { throw 'Paquete incompleto: falta app\dist\main.js' }
if ((Resolve-Path $ReleaseDir).Path -eq (Resolve-Path $InstallDir).Path) {
    throw 'Ejecuta update.ps1 desde el paquete nuevo descomprimido, no desde C:\Warique\scripts.'
}
Write-Step "Actualizando Warique $($config.version) -> $newVersion"

Write-Step 'Respaldo previo'
& (Join-Path $PSScriptRoot 'backup.ps1') -InstallDir $InstallDir -Tag 'antes-de-actualizar'
if ($LASTEXITCODE -eq 1) { throw 'El respaldo fallo; no se actualizara. Revisa logs\backup.log.' }

Write-Step 'Reemplazando la aplicacion'
Stop-Service -Name $config.serviceName
if (Test-Path -LiteralPath $previousDir) { Remove-Item -LiteralPath $previousDir -Recurse -Force }
Rename-Item -LiteralPath $appDir -NewName 'app.previous'
try {
    Copy-Tree (Join-Path $ReleaseDir 'app') $appDir
} catch {
    Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue
    Rename-Item -LiteralPath $previousDir -NewName 'app'
    Start-Service -Name $config.serviceName
    throw
}

Write-Step 'Verificando'
$health = Start-AndCheck
if (-not $health) {
    Write-Warn 'La nueva version no respondio. Volviendo a la anterior...'
    Stop-Service -Name $config.serviceName -ErrorAction SilentlyContinue
    $failedDir = Join-Path $InstallDir ('app.fallida-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Rename-Item -LiteralPath $appDir -NewName (Split-Path $failedDir -Leaf)
    Rename-Item -LiteralPath $previousDir -NewName 'app'
    if (Start-AndCheck) { throw "Actualizacion revertida: sigue funcionando $($config.version). Revisa logs\warique.err.log." }
    throw 'La version anterior tampoco responde. Revisa logs\warique.err.log y el servicio de MySQL.'
}

# Scripts and service wrapper are updated only after the new app is confirmed healthy
Copy-Item -Path (Join-Path $PSScriptRoot '*.ps1') -Destination (Join-Path $InstallDir 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $ReleaseDir 'VERSION') -Destination $InstallDir -Force
$config.version = $newVersion
Save-DeployConfig $InstallDir $config
Write-Ok "Warique $($health.version) en linea. La version anterior queda en app.previous."
Write-Host "`nActualizacion terminada. Recarga la app en los celulares." -ForegroundColor Green
