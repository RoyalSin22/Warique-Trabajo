<#
.SYNOPSIS
  Respaldo de la base de datos de Warique (mysqldump comprimido), con retencion y copia externa.
.DESCRIPTION
  Lo ejecuta todos los dias la tarea programada "Warique - Respaldo diario" (cuenta SYSTEM).
  Tambien se puede ejecutar a mano. Codigos de salida:
    0 = respaldo y copia externa correctos
    1 = el respaldo fallo
    2 = respaldo local correcto, pero la copia externa no estaba disponible (USB desconectado)
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Warique',
    # Omite la copia externa (por ejemplo, el respaldo de seguridad previo a una restauracion)
    [switch]$NoCopy,
    # Se agrega al nombre del archivo: diario, manual, antes-de-actualizar...
    [ValidatePattern('^[a-z0-9-]{1,30}$')]
    [string]$Tag = 'manual'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-DeployConfig $InstallDir
New-Item -ItemType Directory -Force -Path $config.logDir, $config.backupDir | Out-Null
$logFile = Join-Path $config.logDir 'backup.log'
$statusFile = Join-Path $config.backupDir 'ultimo-respaldo.json'

function Write-BackupLog([string]$Level, [string]$Message) {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Save-Status([hashtable]$Status) {
    $Status.time = (Get-Date).ToString('s')
    Write-Utf8File $statusFile (New-Object psobject -Property $Status | ConvertTo-Json)
}

function Remove-OldBackups([string]$Directory) {
    $limit = (Get-Date).AddDays(-[int]$config.retentionDays)
    Get-ChildItem -LiteralPath $Directory -Filter 'warique-*.zip' -File |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-BackupLog 'INFO' "Eliminado por antiguedad: $($_.Name)"
        }
}

$sqlFile = $null
try {
    $name = 'warique-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Tag
    $sqlFile = Join-Path $config.backupDir "$name.sql"
    $zipFile = Join-Path $config.backupDir "$name.zip"

    # --single-transaction: consistent snapshot of InnoDB without locking the restaurant out
    # --result-file: mysqldump writes the file itself (no PowerShell re-encoding)
    $result = Invoke-Native (Get-ExePath $config.mysqlBinDir 'mysqldump') @(
        "--defaults-extra-file=$($config.backupOptionFile)",
        '--single-transaction', '--quick', '--routines', '--triggers', '--no-tablespaces',
        '--default-character-set=utf8mb4', "--result-file=$sqlFile",
        '--databases', $config.database)
    if ($result.ExitCode -ne 0) { throw "mysqldump termino con codigo $($result.ExitCode): $($result.StdErr.Trim())" }

    # A dump cut short (disk full, killed process) has no completion marker
    $lastLine = Get-Content -LiteralPath $sqlFile -Tail 1 -Encoding UTF8
    if ($lastLine -notmatch '^-- Dump completed') { throw 'El archivo de respaldo esta incompleto.' }

    Compress-Archive -LiteralPath $sqlFile -DestinationPath $zipFile -CompressionLevel Optimal
    Remove-Item -LiteralPath $sqlFile -Force
    $sqlFile = $null
    $zip = Get-Item -LiteralPath $zipFile
    $hash = (Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash
    Write-BackupLog 'INFO' ("Respaldo creado: {0} ({1:N0} KB, SHA256 {2})" -f $zip.Name, ($zip.Length / 1KB), $hash)
    Remove-OldBackups $config.backupDir

    $copied = $false
    $exitCode = 0
    if (-not $NoCopy -and $config.backupCopyDir) {
        if (Test-Path -LiteralPath $config.backupCopyDir -PathType Container) {
            Copy-Item -LiteralPath $zipFile -Destination $config.backupCopyDir -Force
            $copiedHash = (Get-FileHash -LiteralPath (Join-Path $config.backupCopyDir $zip.Name) -Algorithm SHA256).Hash
            if ($copiedHash -ne $hash) { throw 'La copia externa no coincide con el original (SHA256).' }
            Remove-OldBackups $config.backupCopyDir
            $copied = $true
            Write-BackupLog 'INFO' "Copia externa en $($config.backupCopyDir)"
        } else {
            $exitCode = 2
            Write-BackupLog 'WARN' "La carpeta de copia externa no esta disponible: $($config.backupCopyDir)"
        }
    }

    Save-Status @{ ok = $true; file = $zip.Name; sizeBytes = $zip.Length; sha256 = $hash; copied = $copied; error = $null }
    exit $exitCode
} catch {
    Write-BackupLog 'ERROR' $_.Exception.Message
    Save-Status @{ ok = $false; file = $null; sizeBytes = 0; sha256 = $null; copied = $false; error = $_.Exception.Message }
    exit 1
} finally {
    if ($sqlFile -and (Test-Path -LiteralPath $sqlFile)) { Remove-Item -LiteralPath $sqlFile -Force }
}
