<#
.SYNOPSIS
  Diagnostico rapido de Warique: servicio, base de datos (y cambios de esquema pendientes), ultimo
  respaldo, disco y direcciones.
  No cambia nada. Util para soporte por telefono:
    powershell -ExecutionPolicy Bypass -File C:\Warique\scripts\status.ps1
#>
[CmdletBinding()]
param([string]$InstallDir = 'C:\Warique')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$config = Get-DeployConfig $InstallDir
$problems = 0

function Show([bool]$Ok, [string]$Message) {
    if ($Ok) { Write-Ok $Message } else { Write-Warn $Message; $script:problems++ }
}

Write-Step "Warique $($config.version) en $InstallDir"
foreach ($name in @($config.serviceName, $config.mysqlService)) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($service) { Show ($service.Status -eq 'Running') "Servicio ${name}: $($service.Status)" }
    else { Show $false "Servicio ${name}: no existe" }
}

try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($config.port)/api/health" -TimeoutSec 5
    Show ($health.status -eq 'ok') ("API: {0}, base de datos {1}, desfase UTC {2} min, activa hace {3:N0} min" -f `
            $health.status, $health.database, $health.dbUtcOffsetMinutes, ($health.uptimeSeconds / 60))
} catch {
    Show $false "API: no responde en el puerto $($config.port) ($($_.Exception.Message))"
}

# Read-only account: never needs the MySQL root password
$migrationsDir = Get-InstalledMigrationsDir $InstallDir
if (Test-Path -LiteralPath $migrationsDir) {
    try {
        $pending = @(Get-PendingMigrations $config.mysqlBinDir $config.backupOptionFile $config.database $migrationsDir)
        if ($pending.Count -eq 0) {
            Show $true 'Esquema de la base de datos al dia'
        } else {
            Show $false ("Cambios de base de datos SIN aplicar: {0}. Vuelve a ejecutar update.ps1 desde el paquete de la version {1}." -f `
                    (($pending | ForEach-Object { $_.BaseName }) -join ', '), $config.version)
        }
    } catch {
        Show $false "No se pudo revisar el esquema de la base de datos: $($_.Exception.Message)"
    }
}

$statusFile = Join-Path $config.logDir 'ultimo-respaldo.json'
if (Test-Path -LiteralPath $statusFile) {
    $last = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $age = (Get-Date) - [datetime]$last.time
    if ($last.ok) {
        Show ($age.TotalHours -lt 26) ("Ultimo respaldo: {0} (hace {1:N0} h), copia externa: {2}" -f $last.file, $age.TotalHours, $(if ($last.copied) { 'si' } else { 'NO' }))
        if ($config.backupCopyDir -and -not $last.copied) { Show $false "La copia externa no se hizo: revisa $($config.backupCopyDir)" }
    } else {
        Show $false "Ultimo respaldo FALLO hace $([int]$age.TotalHours) h: $($last.error)"
    }
} else {
    Show $false 'Todavia no hay respaldos'
}
$task = Get-ScheduledTask -TaskName 'Warique - Respaldo diario' -ErrorAction SilentlyContinue
if ($task) {
    $info = $task | Get-ScheduledTaskInfo
    Show ($task.State -ne 'Disabled') "Tarea de respaldo: $($task.State), proxima ejecucion $($info.NextRunTime)"
} else {
    Show $false 'No existe la tarea programada de respaldo'
}

$drive = Get-PSDrive -Name ($InstallDir.Substring(0, 1))
$freeGb = [math]::Round($drive.Free / 1GB, 1)
Show ($freeGb -ge 5) "Espacio libre en $($drive.Name): $freeGb GB"

Write-Step 'Direcciones para los celulares'
foreach ($ip in @(Get-LanAddresses)) { Write-Host "    http://$($ip):$($config.port)" }

$errLog = Join-Path $config.logDir "$($config.serviceName).err.log"
if ((Test-Path -LiteralPath $errLog) -and (Get-Item -LiteralPath $errLog).Length -gt 0) {
    Write-Step 'Ultimas lineas del registro de errores'
    Get-Content -LiteralPath $errLog -Tail 15 -Encoding UTF8 | ForEach-Object { Write-Host "    $_" }
}

if ($problems -eq 0) { Write-Host "`nTodo en orden." -ForegroundColor Green }
else { Write-Host "`n$problems problema(s) encontrado(s)." -ForegroundColor Yellow; exit 1 }
