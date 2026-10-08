<#
.SYNOPSIS
  Lo ejecuta Warique-Setup.exe: corre install.ps1 o update.ps1 y deja el resultado para el asistente.
.DESCRIPTION
  No hace falta ejecutarlo a mano. Escribe dos archivos junto a -ResultFile:
    resultado.txt  primera linea OK o ERROR; luego las direcciones para los celulares
    resultado.log  todo lo que mostraron los scripts (para soporte)
  Las claves llegan por variables de entorno (WARIQUE_MYSQL_ADMIN_PASSWORD, OWNER_*), nunca por
  la linea de comandos, donde otros procesos podrian leerlas.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('install', 'update')]
    [string]$Mode,
    [Parameter(Mandatory = $true)]
    [string]$ResultFile,
    [switch]$GoogleDrive,
    [switch]$MarkNetworkPrivate,
    # Vacio = detectar (lo normal: un solo MySQL en la PC)
    [string]$MySqlService = '',
    [string]$InstallDir = 'C:\Warique'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$logFile = [IO.Path]::ChangeExtension($ResultFile, '.log')
Remove-Item -LiteralPath $ResultFile -Force -ErrorAction SilentlyContinue
Start-Transcript -LiteralPath $logFile -Force | Out-Null
$ok = $false
try {
    if ($Mode -eq 'install') {
        & (Join-Path $PSScriptRoot 'install.ps1') -InstallDir $InstallDir -AssumeYes -MySqlService $MySqlService `
            -GoogleDrive:$GoogleDrive -MarkNetworkPrivate:$MarkNetworkPrivate
    } else {
        & (Join-Path $PSScriptRoot 'update.ps1') -InstallDir $InstallDir
    }
    $ok = $true
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Stop-Transcript | Out-Null
}

$lines = @()
if ($ok) {
    $lines += 'OK'
    $port = (Get-DeployConfig $InstallDir).port
    foreach ($ip in @(Get-LanAddresses)) { $lines += "http://$($ip):$port" }
} else {
    $lines += 'ERROR'
}
Write-Utf8File $ResultFile (($lines -join "`r`n") + "`r`n")
if (-not $ok) { exit 1 }
