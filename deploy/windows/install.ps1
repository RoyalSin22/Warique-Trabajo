<#
.SYNOPSIS
  Instala Warique en la PC del local como servicio de Windows.
.DESCRIPTION
  Ejecutar como administrador desde la carpeta del paquete descomprimido:
    powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -GoogleDrive

  Pasos (cada uno se puede repetir sin romper nada):
   1. Verifica Node.js 22+ y el servicio de MySQL; ajusta my.ini (UTC y solo acceso local) con confirmacion.
   2. Crea la base de datos (si no existe) y los usuarios de MySQL con claves aleatorias.
   3. Copia la aplicacion a C:\Warique y genera la configuracion (.env) con permisos restringidos.
   4. Registra el servicio "Warique" (WinSW, cuenta LocalService, reinicio automatico).
   5. Abre el puerto en el firewall (solo red privada), desactiva la suspension y fija las horas activas.
   6. Programa el respaldo diario y hace un primer respaldo de prueba.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Warique',
    # Nombre del servicio de MySQL (MySQL84, MySQL80...). Vacio = detectar.
    [string]$MySqlService = '',
    [int]$MySqlPort = 3306,
    [ValidateRange(1024, 65535)]
    [int]$Port = 3000,
    # After closing (the restaurant serves 11:00-18:00). If the PC is already off, the task runs
    # as soon as it is turned on (StartWhenAvailable)
    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$BackupTime = '18:30',
    # Segunda copia del respaldo: USB, disco externo o carpeta sincronizada (OneDrive/Google Drive)
    [string]$BackupCopyDir = '',
    # Usa la carpeta de Google Drive para escritorio (modo "duplicar archivos") como copia externa:
    # <perfil>\My Drive\RespaldosWarique o <perfil>\Mi unidad\RespaldosWarique
    [switch]$GoogleDrive,
    [ValidateRange(3, 365)]
    [int]$RetentionDays = 30,
    # Horas en las que Windows Update no reinicia la PC (maximo 18 horas). Atencion 11:00-18:00:
    # se cubre desde la preparacion (08:00) hasta despues del cierre de caja (22:00)
    [ValidateRange(0, 23)]
    [int]$ActiveHoursStart = 8,
    [ValidateRange(0, 23)]
    [int]$ActiveHoursEnd = 22,
    [switch]$SkipWindowsSettings
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$ServiceName = 'warique'
$Database = 'warique_orders'
$ReleaseDir = Split-Path $PSScriptRoot -Parent
$paths = @{
    App     = Join-Path $InstallDir 'app'
    Config  = Join-Path $InstallDir 'config'
    Logs    = Join-Path $InstallDir 'logs'
    Backups = Join-Path $InstallDir 'backups'
    Scripts = Join-Path $InstallDir 'scripts'
    Service = Join-Path $InstallDir 'service'
}
$envFile = Join-Path $paths.Config '.env'
$backupOptionFile = Join-Path $paths.Config 'backup.cnf'
$adminOptionFile = Join-Path $paths.Config ('admin-' + [Guid]::NewGuid().ToString('N') + '.cnf')
$setupSqlFile = Join-Path $paths.Config ('setup-' + [Guid]::NewGuid().ToString('N') + '.sql')

function Confirm-Choice([string]$Question) {
    return ((Read-Host "$Question [S/N]") -match '^[sSyY]')
}

# Sets key=value lines inside [mysqld]. Returns $true when the file changed.
function Set-MySqlIniValues([string]$IniPath, [hashtable]$Values) {
    $lines = New-Object Collections.Generic.List[string]
    $lines.AddRange([string[]](Get-Content -LiteralPath $IniPath))
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '[mysqld]') { $start = $i; break } }
    if ($start -lt 0) { throw "No se encontro la seccion [mysqld] en $IniPath" }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }

    $changed = $false
    foreach ($key in $Values.Keys) {
        $wanted = "$key=$($Values[$key])"
        # MySQL accepts both default-time-zone and default_time_zone (Regex.Escape keeps '-')
        $pattern = '^\s*' + ([regex]::Escape($key) -replace '[-_]', '[-_]') + '\s*='
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match $pattern) {
                $found = $true
                if ($lines[$i].Trim() -ne $wanted) { $lines[$i] = $wanted; $changed = $true }
            }
        }
        if (-not $found) { $lines.Insert($start + 1, $wanted); $end++; $changed = $true }
    }
    if ($changed) {
        Copy-Item -LiteralPath $IniPath -Destination ("$IniPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        [IO.File]::WriteAllLines($IniPath, $lines, (New-Object Text.UTF8Encoding($false)))
    }
    return $changed
}

function Write-EnvFile([string]$DatabaseUrl) {
    if (Test-Path -LiteralPath $envFile) {
        # Re-install: keep JWT_SECRET (active sessions) and any manual setting; refresh the DB URL
        $lines = Get-Content -LiteralPath $envFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^DATABASE_URL=') { "DATABASE_URL=`"$DatabaseUrl`"" }
            elseif ($_ -match '^PORT=') { "PORT=$Port" }
            else { $_ }
        }
        Write-Utf8File $envFile (($lines -join "`r`n") + "`r`n")
    } else {
        Write-Utf8File $envFile (@(
            '# Generado por install.ps1. Contiene secretos: no copiar ni compartir.',
            "PORT=$Port",
            "DATABASE_URL=`"$DatabaseUrl`"",
            "JWT_SECRET=$(New-RandomSecret 48)",
            'JWT_EXPIRES_IN_SECONDS=43200',
            'BUSINESS_UTC_OFFSET_MINUTES=-300',
            'CORS_ORIGINS='
        ) -join "`r`n")
    }
}

try {
    Assert-Administrator
    foreach ($required in @('app\dist\main.js', 'app\public\index.html', 'service\WinSW-x64.exe', 'database\schema.sql')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $required))) { throw "Paquete incompleto: falta $required" }
    }
    $version = (Get-Content -LiteralPath (Join-Path $ReleaseDir 'VERSION') -Raw).Trim()
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        throw "Warique ya esta instalado. Para una version nueva usa scripts\update.ps1."
    }
    if ($GoogleDrive) {
        if ($BackupCopyDir) { throw 'Usa -GoogleDrive o -BackupCopyDir, no ambos.' }
        $driveFolders = @(Find-GoogleDriveMirrorFolder)
        if ($driveFolders.Count -eq 0) {
            throw ('No se encontro la carpeta de Google Drive (C:\Users\<usuario>\My Drive o Mi unidad). ' +
                'Instala Google Drive para escritorio, inicia sesion con la cuenta del dueno y en ' +
                'Preferencias > Mi unidad elige "Duplicar archivos" (Mirror files). Ver GUIA-INSTALACION.md.')
        }
        $driveFolder = $driveFolders[0]
        if ($driveFolders.Count -gt 1) {
            for ($i = 0; $i -lt $driveFolders.Count; $i++) { Write-Host "    [$($i + 1)] $($driveFolders[$i])" }
            $choice = [int](Read-Host 'Carpeta de Google Drive del dueno (numero)')
            if ($choice -lt 1 -or $choice -gt $driveFolders.Count) { throw 'Opcion invalida.' }
            $driveFolder = $driveFolders[$choice - 1]
        }
        $BackupCopyDir = Join-Path $driveFolder 'RespaldosWarique'
    }
    if ($BackupCopyDir) {
        if (Test-GoogleDriveStreamPath $BackupCopyDir) {
            throw ("$BackupCopyDir esta en la unidad virtual de Google Drive (modo 'Transmitir archivos'), " +
                'que la tarea de respaldo (cuenta SYSTEM) no puede ver. Cambia Google Drive a "Duplicar archivos" ' +
                'y usa -GoogleDrive.')
        }
        New-Item -ItemType Directory -Force -Path $BackupCopyDir | Out-Null
    }
    if ((($ActiveHoursEnd - $ActiveHoursStart + 24) % 24) -gt 18) {
        throw 'Windows permite como maximo 18 horas activas. Ajusta -ActiveHoursStart/-ActiveHoursEnd.'
    }

    # ---------------------------------------------------------------- 1. Requisitos
    Write-Step "Instalando Warique $version en $InstallDir"
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $node) { throw 'No se encontro Node.js. Instala Node.js 22 LTS (nodejs.org) y abre una nueva ventana.' }
    $nodeVersion = (& $node.Source --version).Trim()
    if ([int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 22) { throw "Se requiere Node.js 22 o superior (hay $nodeVersion)." }
    Write-Ok "Node.js $nodeVersion ($($node.Source))"

    if (-not $MySqlService) {
        $candidates = @(Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue)
        if ($candidates.Count -ne 1) {
            throw "No se pudo detectar el servicio de MySQL ($($candidates.Count) encontrados). Indica -MySqlService."
        }
        $MySqlService = $candidates[0].Name
    }
    $mysql = Get-MySqlServiceInfo $MySqlService
    Set-Service -Name $MySqlService -StartupType Automatic
    if ($mysql.State -ne 'Running') { Start-Service -Name $MySqlService }
    Write-Ok "MySQL: servicio $MySqlService (inicio automatico), binarios en $($mysql.BinDir)"

    if ($mysql.IniPath -and (Test-Path -LiteralPath $mysql.IniPath)) {
        $iniValues = @{
            'default-time-zone'         = "'+00:00'"   # the API stores and reads UTC
            'bind-address'              = '127.0.0.1' # MySQL not reachable from the network
            'loose-mysqlx-bind-address' = '127.0.0.1' # X Protocol too ("loose": no error if disabled)
        }
        Write-Host "    my.ini: $($mysql.IniPath)"
        Write-Host "    Se fijara en [mysqld]: $(($iniValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
        if (Confirm-Choice '    Aplicar estos ajustes en my.ini y reiniciar MySQL?') {
            if (Set-MySqlIniValues $mysql.IniPath $iniValues) {
                Restart-Service -Name $MySqlService -Force
                Write-Ok 'my.ini actualizado (copia .bak creada) y MySQL reiniciado'
            } else {
                Write-Ok 'my.ini ya tenia los ajustes'
            }
        } else {
            Write-Warn 'my.ini sin cambios: la verificacion de zona horaria puede fallar.'
        }
    } else {
        Write-Warn 'No se encontro my.ini del servicio; revisa a mano default-time-zone y bind-address.'
    }

    # ---------------------------------------------------------------- 2. Base de datos
    Write-Step 'Base de datos'
    New-Item -ItemType Directory -Force -Path $paths.Config | Out-Null
    Set-RestrictedAcl $paths.Config
    $rootPassword = Read-PlainSecret 'Clave del usuario root de MySQL (no se guarda)'
    New-MySqlOptionFile $adminOptionFile 'root' $rootPassword $MySqlPort
    $rootPassword = $null

    $offset = Invoke-MySqlQuery $mysql.BinDir $adminOptionFile 'SELECT TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), NOW())'
    if ($offset -ne '0') {
        throw "MySQL no esta en UTC (diferencia $offset min). Agrega default-time-zone='+00:00' en my.ini y reinicia MySQL."
    }
    Write-Ok 'MySQL en UTC'

    $exists = Invoke-MySqlQuery $mysql.BinDir $adminOptionFile "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$Database'"
    if ($exists -eq '0') {
        Invoke-MySqlFile $mysql.BinDir $adminOptionFile (Join-Path $ReleaseDir 'database\schema.sql')
        Write-Ok "Base de datos $Database creada"
    } else {
        Write-Ok "Base de datos $Database ya existe (se conserva)"
    }

    # Random passwords that nobody needs to remember; rotated on every install run
    $appPassword = New-RandomSecret 24
    $backupPassword = New-RandomSecret 24
    $setupSql = @(
        (Get-Content -LiteralPath (Join-Path $ReleaseDir 'database\app-user.sql') -Raw -Encoding UTF8).Replace('CHANGE_ME', $appPassword),
        "ALTER USER 'warique_app'@'localhost' IDENTIFIED BY '$appPassword';",
        (Get-Content -LiteralPath (Join-Path $ReleaseDir 'database\backup-user.sql') -Raw -Encoding UTF8).Replace('CHANGE_ME', $backupPassword),
        "ALTER USER 'warique_backup'@'localhost' IDENTIFIED BY '$backupPassword';"
    ) -join "`r`n"
    Write-Utf8File $setupSqlFile $setupSql
    Set-RestrictedAcl $setupSqlFile
    Invoke-MySqlFile $mysql.BinDir $adminOptionFile $setupSqlFile
    Remove-Item -LiteralPath $setupSqlFile -Force
    Write-Ok 'Usuarios warique_app (sin DELETE ni DDL) y warique_backup (solo lectura) listos'

    # ---------------------------------------------------------------- 3. Archivos y configuracion
    Write-Step 'Copiando la aplicacion'
    foreach ($dir in $paths.Values) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $robocopy = Start-Process robocopy.exe -ArgumentList (ConvertTo-ArgumentString @(
            (Join-Path $ReleaseDir 'app'), $paths.App, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')) -NoNewWindow -Wait -PassThru
    if ($robocopy.ExitCode -ge 8) { throw "robocopy fallo con codigo $($robocopy.ExitCode)" }
    Copy-Item -Path (Join-Path $PSScriptRoot '*.ps1') -Destination $paths.Scripts -Force
    Copy-Item -LiteralPath (Join-Path $ReleaseDir 'service\WinSW-x64.exe') -Destination (Join-Path $paths.Service 'warique.exe') -Force
    Copy-Item -LiteralPath (Join-Path $ReleaseDir 'VERSION') -Destination $InstallDir -Force
    Write-Ok "Aplicacion en $($paths.App)"

    $encodedPassword = [Uri]::EscapeDataString($appPassword)
    Write-EnvFile "mysql://warique_app:$encodedPassword@localhost:$MySqlPort/$Database"
    Set-EnvFileValue $envFile 'BACKUP_STATUS_FILE' (Join-Path $paths.Logs 'ultimo-respaldo.json')
    New-MySqlOptionFile $backupOptionFile 'warique_backup' $backupPassword $MySqlPort
    $appPassword = $null
    $backupPassword = $null

    # Least privilege: the service account only reads the app and .env and writes its logs
    Set-RestrictedAcl $InstallDir @("$($script:SidLocalService):(OI)(CI)RX")
    Set-RestrictedAcl $paths.Config
    Set-RestrictedAcl $paths.Backups
    Set-RestrictedAcl $envFile @("$($script:SidLocalService):R")
    Set-RestrictedAcl $backupOptionFile
    Set-RestrictedAcl $paths.Logs @("$($script:SidLocalService):(OI)(CI)M")
    Write-Ok 'Configuracion en config\.env (solo administradores y el servicio pueden leerla)'

    $deployConfig = [ordered]@{
        version          = $version
        installDir       = $InstallDir
        serviceName      = $ServiceName
        port             = $Port
        database         = $Database
        mysqlService     = $MySqlService
        mysqlBinDir      = $mysql.BinDir
        mysqlPort        = $MySqlPort
        logDir           = $paths.Logs
        backupDir        = $paths.Backups
        backupCopyDir    = $BackupCopyDir
        retentionDays    = $RetentionDays
        backupOptionFile = $backupOptionFile
    }
    Save-DeployConfig $InstallDir $deployConfig

    # ---------------------------------------------------------------- Cuenta del dueno
    $owners = Invoke-MySqlQuery $mysql.BinDir $adminOptionFile "SELECT COUNT(*) FROM $Database.users WHERE role = 'OWNER' AND is_active = 1"
    if ($owners -eq '0') {
        Write-Step 'Cuenta del dueno (para entrar a la app)'
        $env:OWNER_USERNAME = (Read-Host 'Usuario (minusculas, sin espacios, ej. dueno)').Trim().ToLower()
        $env:OWNER_FULL_NAME = Read-Host 'Nombre completo'
        $env:OWNER_PASSWORD = Read-NewPassword 'Clave del dueno' 10
        $env:WARIQUE_ENV_FILE = $envFile
        try {
            $result = Invoke-Native $node.Source @('dist\cli\create-owner.js') $paths.App
            if ($result.ExitCode -ne 0) { throw "No se pudo crear la cuenta: $($result.StdErr.Trim())" }
            Write-Ok $result.StdOut.Trim()
        } finally {
            Remove-Item Env:OWNER_USERNAME, Env:OWNER_FULL_NAME, Env:OWNER_PASSWORD, Env:WARIQUE_ENV_FILE -ErrorAction SilentlyContinue
        }
    } else {
        Write-Ok 'Ya existe una cuenta de dueno activa'
    }

    # ---------------------------------------------------------------- 4. Servicio de Windows
    Write-Step 'Registrando el servicio de Windows'
    $x = { param($value) [Security.SecurityElement]::Escape([string]$value) }
    $serviceXml = @"
<service>
  <id>$ServiceName</id>
  <name>Warique</name>
  <description>Warique: pedidos, cocina y cobros (API y app web en el puerto $Port)</description>
  <executable>$(& $x $node.Source)</executable>
  <arguments>dist\main.js</arguments>
  <workingdirectory>$(& $x $paths.App)</workingdirectory>
  <env name="NODE_ENV" value="production" />
  <env name="WARIQUE_ENV_FILE" value="$(& $x $envFile)" />
  <depend>$(& $x $MySqlService)</depend>
  <startmode>Automatic</startmode>
  <stoptimeout>15 sec</stoptimeout>
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="30 sec" />
  <onfailure action="restart" delay="60 sec" />
  <resetfailure>1 hour</resetfailure>
  <logpath>$(& $x $paths.Logs)</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
</service>
"@
    Write-Utf8File (Join-Path $paths.Service 'warique.xml') $serviceXml
    $winsw = Join-Path $paths.Service 'warique.exe'
    $result = Invoke-Native $winsw @('install') $paths.Service
    if ($result.ExitCode -ne 0) { throw "WinSW no pudo registrar el servicio: $($result.StdErr.Trim()) $($result.StdOut.Trim())" }
    # Low-privilege built-in account (no password, no access to user files)
    $result = Invoke-Native 'sc.exe' @('config', $ServiceName, 'obj=', 'NT AUTHORITY\LocalService', 'password=', '')
    if ($result.ExitCode -ne 0) { throw "No se pudo asignar la cuenta LocalService: $($result.StdOut.Trim())" }
    Write-Ok 'Servicio "Warique" registrado (inicio automatico, reinicio ante fallos, cuenta LocalService)'

    # ---------------------------------------------------------------- 5. Red y Windows
    Write-Step 'Firewall y red'
    Get-NetFirewallRule -Name 'Warique-HTTP' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name 'Warique-HTTP' -DisplayName 'Warique (pedidos)' -Direction Inbound `
        -Protocol TCP -LocalPort $Port -Action Allow -Profile Private | Out-Null
    Write-Ok "Puerto $Port abierto solo para redes privadas"
    foreach ($netProfile in @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' })) {
        Write-Warn "La red '$($netProfile.Name)' es Publica: los celulares no podran conectarse."
        if (Confirm-Choice "    Marcar '$($netProfile.Name)' como red Privada? (solo si es la red del local)") {
            Set-NetConnectionProfile -InterfaceIndex $netProfile.InterfaceIndex -NetworkCategory Private
            Write-Ok "'$($netProfile.Name)' ahora es Privada"
        }
    }

    if (-not $SkipWindowsSettings) {
        Write-Step 'Energia y Windows Update'
        & powercfg.exe /change standby-timeout-ac 0 | Out-Null
        & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
        & powercfg.exe /hibernate off | Out-Null   # also disables Fast Startup (cleaner restarts)
        Write-Ok 'La PC no se suspende ni hiberna conectada a la corriente'
        if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) {
            Write-Warn 'Es una laptop: debe quedar siempre conectada al cargador.'
        }
        $updateKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        New-Item -Path $updateKey -Force | Out-Null
        foreach ($setting in @(@('ActiveHoursStart', $ActiveHoursStart), @('ActiveHoursEnd', $ActiveHoursEnd), @('SmartActiveHoursState', 0))) {
            New-ItemProperty -Path $updateKey -Name $setting[0] -Value $setting[1] -PropertyType DWord -Force | Out-Null
        }
        Write-Ok "Windows Update no reiniciara entre las $($ActiveHoursStart):00 y las $($ActiveHoursEnd):00"
    }

    # ---------------------------------------------------------------- 6. Respaldo diario
    Write-Step 'Respaldo diario'
    $backupScript = Join-Path $paths.Scripts 'backup.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -ExecutionPolicy Bypass -File `"$backupScript`" -InstallDir `"$InstallDir`" -Tag diario")
    $trigger = New-ScheduledTaskTrigger -Daily -At $BackupTime
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # StartWhenAvailable: if the PC was off at that time, it runs as soon as it is turned on
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName 'Warique - Respaldo diario' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Ok "Programado todos los dias a las $BackupTime (cuenta SYSTEM)"
    if (-not $BackupCopyDir) { Write-Warn 'Sin -BackupCopyDir: si el disco falla se pierden tambien los respaldos.' }

    # ---------------------------------------------------------------- Inicio y verificacion
    Write-Step 'Iniciando Warique'
    Start-Service -Name $ServiceName
    $health = Wait-Health $Port 90
    if (-not $health) { throw "El servicio no respondio. Revisa $($paths.Logs)\warique.err.log" }
    if ($health.dbUtcOffsetMinutes -ne 0) { throw 'La base de datos no esta en UTC (ver my.ini).' }
    Write-Ok "Warique $($health.version) en linea"

    # Test through the scheduled task itself: it runs as SYSTEM, which may not see folders that
    # this administrator session sees (mapped drives, Google Drive in streaming mode)
    Write-Step 'Respaldo de prueba (como lo hara cada noche)'
    $startedAt = Get-Date
    Start-ScheduledTask -TaskName 'Warique - Respaldo diario'
    $deadline = $startedAt.AddMinutes(5)
    do {
        Start-Sleep -Seconds 3
        $taskInfo = Get-ScheduledTaskInfo -TaskName 'Warique - Respaldo diario'
        $task = Get-ScheduledTask -TaskName 'Warique - Respaldo diario'
    } while (($task.State -eq 'Running' -or $taskInfo.LastRunTime -lt $startedAt.AddSeconds(-5)) -and (Get-Date) -lt $deadline)
    $statusFile = Join-Path $paths.Logs 'ultimo-respaldo.json'
    $lastBackup = if (Test-Path -LiteralPath $statusFile) { Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    if (-not $lastBackup -or -not $lastBackup.ok) {
        Write-Warn "El respaldo de prueba fallo (resultado $($taskInfo.LastTaskResult)): revisa logs\backup.log"
    } elseif ($BackupCopyDir -and -not $lastBackup.copied) {
        Write-Warn "El respaldo local funciona, pero la tarea no pudo copiar a $BackupCopyDir."
    } else {
        Write-Ok "Respaldo de prueba correcto: $($lastBackup.file)$(if ($lastBackup.copied) { ", copiado a $BackupCopyDir" })"
        if ($GoogleDrive) {
            Write-Warn 'Google Drive solo sube los archivos mientras la sesion de Windows del dueno esta iniciada.'
            Write-Host '    Revisa en drive.google.com que aparezca la carpeta RespaldosWarique.'
        }
    }

    Write-Host "`nInstalacion terminada." -ForegroundColor Green
    Write-Host 'Abre la app desde celulares y tablets conectados al Wi-Fi del local:'
    foreach ($ip in @(Get-LanAddresses)) { Write-Host "    http://$($ip):$Port" -ForegroundColor White }
    Write-Host 'En la app: Gestion > Conectar celulares muestra un codigo QR con esta direccion.'
    Write-Host 'Reserva esa IP en el router para que no cambie (direccion MAC de esta PC):'
    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | ForEach-Object { Write-Host "    $($_.Name): $($_.MacAddress)" }
} finally {
    Remove-Item -LiteralPath $adminOptionFile, $setupSqlFile -Force -ErrorAction SilentlyContinue
}
