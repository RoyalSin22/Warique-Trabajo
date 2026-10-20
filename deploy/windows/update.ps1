<#
.SYNOPSIS
  Actualiza Warique a la version del paquete donde esta este script.
.DESCRIPTION
  Ejecutar como administrador desde el paquete NUEVO descomprimido:
    powershell -ExecutionPolicy Bypass -File .\scripts\update.ps1
  1. Respaldo de la base de datos (si falla, no actualiza).
  2. Aplica los cambios de esquema pendientes (database\migrations). Solo entonces pide la
     clave de root de MySQL (o la toma de WARIQUE_MYSQL_ADMIN_PASSWORD). Los cambios solo
     agregan tablas o columnas: la version anterior sigue funcionando si hay que volver.
  3. Detiene el servicio, guarda la version actual en app.previous y copia la nueva.
  4. Inicia y verifica /api/health. Si no responde, vuelve sola a la version anterior.
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

# A build that crashes on start makes Start-Service throw; that must lead to the rollback,
# never abort the script with the restaurant's service stopped (found by the Windows CI job)
function Start-AndCheck {
    try {
        Start-Service -Name $config.serviceName -ErrorAction Stop
    } catch {
        Write-Warn "El servicio no inicio: $($_.Exception.Message)"
        return $null
    }
    return (Wait-Health ([int]$config.port) 90)
}

# Stops the service so that nothing can restart it from the folder being swapped: the service's
# own restart-on-failure would relaunch a crashing build in the middle of the rollback
function Stop-ForSwap {
    Set-Service -Name $config.serviceName -StartupType Disabled
    Stop-Service -Name $config.serviceName -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
        Where-Object { $_.CommandLine -like '*dist\main.js*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Set-Service -Name $config.serviceName -StartupType Automatic
}

# The antivirus may hold files of a freshly copied node_modules for a few seconds
function Rename-WithRetry([string]$Path, [string]$NewName) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { Rename-Item -LiteralPath $Path -NewName $NewName -ErrorAction Stop; return $true }
        catch { Start-Sleep -Seconds 3 }
    }
    return $false
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

Write-Step 'Esquema de la base de datos'
$pending = @(Get-PendingMigrations $config.mysqlBinDir $config.backupOptionFile $config.database (Join-Path $ReleaseDir 'database\migrations'))
if ($pending.Count -eq 0) {
    Write-Ok 'Sin cambios pendientes'
} else {
    Write-Ok ("Pendientes: " + (($pending | ForEach-Object { $_.BaseName }) -join ', '))
    $adminOptionFile = Join-Path $InstallDir ('config\admin-' + [Guid]::NewGuid().ToString('N') + '.cnf')
    $rootPassword = $env:WARIQUE_MYSQL_ADMIN_PASSWORD
    if (-not $rootPassword) { $rootPassword = Read-PlainSecret 'Clave del usuario root de MySQL (no se guarda)' }
    try {
        New-MySqlOptionFile $adminOptionFile 'root' $rootPassword ([int]$config.mysqlPort)
        $rootPassword = $null
        Invoke-Migrations $config.mysqlBinDir $adminOptionFile $config.database $pending
    } finally {
        Remove-Item -LiteralPath $adminOptionFile -Force -ErrorAction SilentlyContinue
    }
}

# Settings introduced by newer versions (idempotent)
Set-EnvFileValue (Join-Path $InstallDir 'config\.env') 'BACKUP_STATUS_FILE' (Join-Path $config.logDir 'ultimo-respaldo.json')

Write-Step 'Reemplazando la aplicacion'
try {
    Stop-Service -Name $config.serviceName -ErrorAction Stop
} catch {
    Write-Warn "El servicio no se detuvo a tiempo ($($_.Exception.Message)); se fuerza"
    Stop-ForSwap
}
try {
    if (Test-Path -LiteralPath $previousDir) { Remove-Item -LiteralPath $previousDir -Recurse -Force }
    Rename-Item -LiteralPath $appDir -NewName 'app.previous'
} catch {
    # A file locked by the antivirus or an open Explorer window: the restaurant keeps the current version
    if (-not (Test-Path -LiteralPath $appDir) -and (Test-Path -LiteralPath $previousDir)) {
        Rename-Item -LiteralPath $previousDir -NewName 'app'
    }
    Start-Service -Name $config.serviceName
    throw "No se pudo apartar la version actual (algun archivo en uso: cierra el Explorador y reintenta): $($_.Exception.Message)"
}
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
    Stop-ForSwap
    $failedDir = Join-Path $InstallDir ('app.fallida-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if ((Rename-WithRetry $appDir (Split-Path $failedDir -Leaf)) -and (Rename-WithRetry $previousDir 'app')) {
        Write-Ok 'Version anterior restituida'
    } else {
        # A file still locked: copy the previous version over the failed one instead of renaming
        Write-Warn 'No se pudo renombrar (archivo en uso); copiando la version anterior encima'
        Copy-Tree $previousDir $appDir
    }
    if (Start-AndCheck) { throw "Actualizacion revertida: sigue funcionando $($config.version). Revisa logs\warique.err.log." }
    throw 'La version anterior tampoco responde. Revisa logs\warique.err.log y el servicio de MySQL.'
}

# Scripts are updated only after the new app is confirmed healthy (the service wrapper
# warique.exe/warique.xml is written by install.ps1 only; updates do not change it)
Copy-Item -Path (Join-Path $PSScriptRoot '*.ps1') -Destination (Join-Path $InstallDir 'scripts') -Force
Copy-Migrations $ReleaseDir $InstallDir

# 0.4.0: MySQL restarts by itself after a crash (installs before 0.4.0 did not set it)
if ($config.mysqlService -and (Get-Service -Name $config.mysqlService -ErrorAction SilentlyContinue)) {
    Set-MySqlServiceRecovery $config.mysqlService
    Write-Ok "MySQL ($($config.mysqlService)) se reinicia solo si falla"
}

# 0.3.0: the nightly backup moved from 18:30 to 19:30 (after the cash count, done by 19:00).
# Only the old default is moved; a time the owner chose with -BackupTime is kept.
$backupTask = Get-ScheduledTask -TaskName 'Warique - Respaldo diario' -ErrorAction SilentlyContinue
if ($backupTask -and $backupTask.Triggers.Count -eq 1 -and
    ([datetime]$backupTask.Triggers[0].StartBoundary).ToString('HH:mm') -eq '18:30') {
    Set-ScheduledTask -TaskName 'Warique - Respaldo diario' -Trigger (New-ScheduledTaskTrigger -Daily -At '19:30') | Out-Null
    Write-Ok 'Respaldo diario movido a las 19:30 (despues del cierre de caja)'
}

Copy-Item -LiteralPath (Join-Path $ReleaseDir 'VERSION') -Destination $InstallDir -Force
$config.version = $newVersion
Save-DeployConfig $InstallDir $config
Write-Ok "Warique $($health.version) en linea. La version anterior queda en app.previous."
Write-Host "`nActualizacion terminada. Recarga la app en los celulares." -ForegroundColor Green
