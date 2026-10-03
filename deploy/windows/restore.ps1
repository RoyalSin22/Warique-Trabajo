<#
.SYNOPSIS
  Restaura la base de datos de Warique desde un respaldo .zip creado por backup.ps1.
.DESCRIPTION
  REEMPLAZA todos los datos actuales. Antes de restaurar crea un respaldo de seguridad
  ("antes-de-restaurar"), detiene el servicio, restaura y vuelve a iniciarlo.
  Pide la clave del usuario administrador de MySQL (root), que no se guarda en ningun archivo.
.EXAMPLE
  .\restore.ps1 -BackupFile 'C:\Warique\backups\warique-20261003-233000-diario.zip'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [string]$InstallDir = 'C:\Warique',
    [string]$AdminUser = 'root',
    # Omite la confirmacion escrita (solo para automatizar)
    [switch]$Force,
    # No detiene ni inicia el servicio (si ya lo detuviste a mano)
    [switch]$NoServiceControl
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-DeployConfig $InstallDir
$BackupFile = (Resolve-Path -LiteralPath $BackupFile).Path
$workDir = Join-Path $config.backupDir ('restaurar-' + [Guid]::NewGuid().ToString('N'))
$adminOptionFile = Join-Path (Join-Path $InstallDir 'config') ('admin-' + [Guid]::NewGuid().ToString('N') + '.cnf')
$serviceStopped = $false

try {
    Write-Step "Verificando $BackupFile"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    Expand-Archive -LiteralPath $BackupFile -DestinationPath $workDir
    $sqlFiles = @(Get-ChildItem -LiteralPath $workDir -Filter '*.sql' -File)
    if ($sqlFiles.Count -ne 1) { throw 'El .zip debe contener exactamente un archivo .sql.' }
    $sqlFile = $sqlFiles[0].FullName
    if ((Get-Content -LiteralPath $sqlFile -Tail 1 -Encoding UTF8) -notmatch '^-- Dump completed') {
        throw 'El respaldo esta incompleto; no se restaurara.'
    }
    Write-Ok "Respaldo completo: $($sqlFiles[0].Name)"

    if (-not $Force) {
        Write-Warn 'Se REEMPLAZARAN todos los pedidos, pagos, platos y usuarios actuales.'
        if ((Read-Host 'Escribe RESTAURAR para continuar') -cne 'RESTAURAR') { throw 'Cancelado por el usuario.' }
    }

    # Automation can provide the password through the environment instead of the prompt
    $adminPassword = $env:WARIQUE_MYSQL_ADMIN_PASSWORD
    if (-not $adminPassword) { $adminPassword = Read-PlainSecret "Clave de MySQL para '$AdminUser'" }
    New-MySqlOptionFile $adminOptionFile $AdminUser $adminPassword ([int]$config.mysqlPort)
    Invoke-MySqlQuery $config.mysqlBinDir $adminOptionFile 'SELECT 1' | Out-Null
    Write-Ok 'Credenciales de MySQL correctas'

    Write-Step 'Respaldo de seguridad del estado actual'
    & (Join-Path $PSScriptRoot 'backup.ps1') -InstallDir $InstallDir -NoCopy -Tag 'antes-de-restaurar'
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el respaldo de seguridad; no se restaurara.' }

    if (-not $NoServiceControl) {
        Write-Step "Deteniendo el servicio $($config.serviceName)"
        Stop-Service -Name $config.serviceName
        $serviceStopped = $true
    }

    Write-Step 'Restaurando (puede tardar unos minutos)'
    Invoke-MySqlFile $config.mysqlBinDir $adminOptionFile $sqlFile
    Write-Ok 'Base de datos restaurada'
} finally {
    Remove-Item -LiteralPath $adminOptionFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    # Even if the restore failed, the restaurant needs the service back
    if ($serviceStopped) {
        Write-Step "Iniciando el servicio $($config.serviceName)"
        Start-Service -Name $config.serviceName
    }
}

if (-not $NoServiceControl) {
    $health = Wait-Health ([int]$config.port) 90
    if (-not $health) { throw 'El servicio no respondio despues de restaurar. Revisa C:\Warique\logs.' }
    Write-Ok "Servicio en linea (version $($health.version))"
}
Write-Host "`nRestauracion terminada." -ForegroundColor Green
