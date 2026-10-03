# CI only: checks a real installation made by deploy/windows/install.ps1 on Windows.
# Runs on Windows PowerShell 5.1, the version the restaurant PC has.
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir,
    [string]$InstallDir = 'C:\Warique',
    [Parameter(Mandatory = $true)][string]$OwnerPassword,
    [Parameter(Mandatory = $true)][string]$DriveCopyDir
)
$ErrorActionPreference = 'Stop'
$failures = New-Object Collections.Generic.List[string]
$base = 'http://127.0.0.1:3000'

function Check([string]$Name, [scriptblock]$Test) {
    try {
        $result = & $Test
        if ($result -eq $false) { throw 'returned false' }
        Write-Host "PASS  $Name" -ForegroundColor Green
    } catch {
        Write-Host "FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Health { Invoke-RestMethod "$base/api/health" -TimeoutSec 5 }

function Wait-Healthy([int]$Seconds = 90, [int]$MaxUptime = [int]::MaxValue) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try { $h = Health; if ($h.status -eq 'ok' -and $h.uptimeSeconds -le $MaxUptime) { return $h } } catch { }
        Start-Sleep -Seconds 2
    }
    throw "not healthy after $Seconds s"
}

function Api([string]$Method, [string]$Path, $Body = $null, [hashtable]$Headers = @{}) {
    $params = @{ Method = $Method; Uri = "$base/api$Path"; Headers = $Headers; ContentType = 'application/json; charset=utf-8' }
    if ($Body -ne $null) { $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5)) }
    Invoke-RestMethod @params
}

function Sids([string]$Path) {
    (Get-Acl -LiteralPath $Path).Access | ForEach-Object {
        try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $_.IdentityReference.Value }
    }
}

# ------------------------------------------------------------------ Service and Windows setup
Check 'service Warique runs as LocalService, automatic start' {
    $svc = Get-CimInstance Win32_Service -Filter "Name='warique'"
    Write-Host "      $($svc.State) $($svc.StartMode) $($svc.StartName)"
    $svc.State -eq 'Running' -and $svc.StartMode -eq 'Auto' -and $svc.StartName -eq 'NT AUTHORITY\LocalService'
}
Check 'health ok and MySQL in UTC (runner clock is Peru time)' {
    $h = Health; Write-Host "      $($h | ConvertTo-Json -Compress)"
    $h.status -eq 'ok' -and $h.dbUtcOffsetMinutes -eq 0
}
Check 'my.ini hardened (time zone, bind-address)' {
    $svc = Get-CimInstance Win32_Service -Filter "Name='MySQL84'"
    $ini = [regex]::Match($svc.PathName, '--defaults-file="?([^"]+?)"?(\s|$)').Groups[1].Value
    $text = Get-Content -LiteralPath $ini -Raw
    $text -match "default-time-zone='\+00:00'" -and $text -match 'bind-address=127\.0\.0\.1'
}
Check 'MySQL listens only on 127.0.0.1' {
    $listen = @(Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction Stop)
    Write-Host "      $($listen.LocalAddress -join ', ')"
    @($listen | Where-Object { $_.LocalAddress -notin @('127.0.0.1') }).Count -eq 0
}
Check 'firewall rule only for Private networks' {
    $rule = Get-NetFirewallRule -Name 'Warique-HTTP'
    $port = ($rule | Get-NetFirewallPortFilter).LocalPort
    "$($rule.Profile)" -eq 'Private' -and "$port" -eq '3000' -and "$($rule.Enabled)" -eq 'True'
}
Check 'Windows Update active hours 08-22' {
    $key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $key.ActiveHoursStart -eq 8 -and $key.ActiveHoursEnd -eq 22
}
Check 'ACL: .env readable by the service only (plus admins/SYSTEM)' {
    $sids = Sids "$InstallDir\config\.env"; Write-Host "      $($sids -join ' ')"
    ($sids -contains 'S-1-5-19') -and -not ($sids -contains 'S-1-5-32-545') -and -not ($sids -contains 'S-1-5-11')
}
Check 'ACL: config and backups closed to Users and the service' {
    foreach ($dir in @('config', 'backups')) {
        $sids = Sids "$InstallDir\$dir"
        if ($sids -contains 'S-1-5-32-545' -or $sids -contains 'S-1-5-11' -or $sids -contains 'S-1-5-19') { throw "$dir : $($sids -join ' ')" }
    }
}
Check 'ACL: logs writable by the service' {
    $rule = (Get-Acl "$InstallDir\logs").Access | Where-Object {
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-19' }
    "$($rule.FileSystemRights)" -match 'Modify'
}
Check 'backup task runs as SYSTEM at 18:30' {
    $task = Get-ScheduledTask -TaskName 'Warique - Respaldo diario'
    $task.Principal.UserId -eq 'SYSTEM' -and ([datetime]$task.Triggers[0].StartBoundary).ToString('HH:mm') -eq '18:30'
}
Check 'install-time backup ran as SYSTEM and reached the Google Drive folder' {
    $status = Get-Content "$InstallDir\logs\ultimo-respaldo.json" -Raw | ConvertFrom-Json
    Write-Host "      $($status | ConvertTo-Json -Compress)"
    $status.ok -and $status.copied -and (Test-Path -LiteralPath (Join-Path $DriveCopyDir $status.file))
}

# ------------------------------------------------------------------ Web app and API
Check 'web app served on the API port with the Flutter CSP' {
    $page = Invoke-WebRequest "$base/" -UseBasicParsing
    $csp = $page.Headers['Content-Security-Policy']
    $page.Content -match 'flutter_bootstrap.js' -and $csp -match 'wasm-unsafe-eval' -and $csp -notmatch 'upgrade-insecure'
}
$owner = Api POST '/auth/login' @{ username = 'duenio'; password = $OwnerPassword }
$auth = @{ Authorization = "Bearer $($owner.accessToken)" }
Check 'owner account created by the installer can log in' { $owner.user.role -eq 'OWNER' }

Check 'business flow: menu, table, waiter, order (idempotent), Yape payment, report' {
    $cat = Api POST '/categories' @{ name = 'Fondos'; sortOrder = 1 } $auth
    $dish = Api POST '/dishes' @{ categoryId = $cat.id; name = 'Ají de gallina'; price = 15.5 } $auth
    $table = Api POST '/tables' @{ label = 'Mesa 1' } $auth
    Api POST '/users' @{ fullName = 'Rosa Mozo'; username = 'rosa'; password = 'Rosa-pass-123'; role = 'WAITER' } $auth | Out-Null
    $waiter = Api POST '/auth/login' @{ username = 'rosa'; password = 'Rosa-pass-123' }
    $wauth = @{ Authorization = "Bearer $($waiter.accessToken)"; 'Idempotency-Key' = 'ci-order-0001' }
    $order = @{ orderType = 'DINE_IN'; tableId = $table.id; items = @(@{ dishId = $dish.id; quantity = 2 }) }
    $first = Api POST '/orders' $order $wauth
    $retry = Api POST '/orders' $order $wauth
    if ($first.id -ne $retry.id) { throw "retry created order $($retry.id)" }
    if ([decimal]$first.total -ne 31) { throw "total $($first.total)" }
    $pay = @{ Authorization = $wauth.Authorization; 'Idempotency-Key' = 'ci-pay-0001' }
    Api POST "/orders/$($first.id)/payments" @{ method = 'YAPE'; amount = 31; operationNumber = 'OP-123456' } $pay | Out-Null
    $paid = Api POST "/orders/$($first.id)/payments" @{ method = 'YAPE'; amount = 31; operationNumber = 'OP-123456' } $pay
    if (@($paid.payments).Count -ne 1) { throw 'payment registered twice' }
    $report = Api GET '/reports/daily' $null $auth
    $payments = Api GET '/reports/payments' $null $auth
    $backup = Api GET '/reports/backup-status' $null $auth
    Write-Host "      sales $($report.sales), op $($payments.payments[0].operationNumber), backup ok=$($backup.ok) copied=$($backup.copied)"
    [decimal]$report.sales -eq 31 -and $payments.payments[0].operationNumber -eq 'OP-123456' -and $backup.ok -and $backup.copied -and -not $backup.needsAttention
}
Check 'accents survive the whole stack (UTF-8)' { (Api GET '/dishes' $null $auth)[0].name -eq 'Ají de gallina' }
Check 'status.ps1 reports everything in order' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\scripts\status.ps1"
    $LASTEXITCODE -eq 0
}

# ------------------------------------------------------------------ Resilience
Check 'service restarts by itself after the Node process dies' {
    $before = (Health).uptimeSeconds
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object CommandLine -like '*dist\main.js*' |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep -Seconds 3
    $h = Wait-Healthy 90 30
    Write-Host "      back after crash, uptime $($h.uptimeSeconds) s (was $before s)"
    $true
}
Check 'service survives a full stop/start (as after a reboot)' {
    Stop-Service warique; Start-Service warique; Wait-Healthy | Out-Null; $true
}

# ------------------------------------------------------------------ Backup / restore
Check 'restore.ps1 brings back the data of a backup' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\scripts\backup.ps1" -Tag manual
    if ($LASTEXITCODE -ne 0) { throw "backup exit $LASTEXITCODE" }
    $zip = Get-ChildItem "$InstallDir\backups" -Filter '*-manual.zip' | Sort-Object LastWriteTime | Select-Object -Last 1
    Api POST '/categories' @{ name = 'Creada despues del respaldo' } $auth | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\scripts\restore.ps1" -BackupFile $zip.FullName -Force
    if ($LASTEXITCODE -ne 0) { throw "restore exit $LASTEXITCODE" }
    $owner2 = Api POST '/auth/login' @{ username = 'duenio'; password = $OwnerPassword }
    $names = (Api GET '/categories?includeInactive=true' $null @{ Authorization = "Bearer $($owner2.accessToken)" }).name
    Write-Host "      categories after restore: $($names -join ', ')"
    ($names -contains 'Fondos') -and -not ($names -contains 'Creada despues del respaldo')
}
Check 'safety backup before restore did not turn the owner card red' {
    $status = Get-Content "$InstallDir\logs\ultimo-respaldo.json" -Raw | ConvertFrom-Json
    $status.copied
}

# ------------------------------------------------------------------ Updates
Check 'update.ps1 installs a release and keeps app.previous' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$ReleaseDir\scripts\update.ps1"
    $LASTEXITCODE -eq 0 -and (Test-Path "$InstallDir\app.previous\dist\main.js") -and (Health).status -eq 'ok'
}
Check 'a broken release is rolled back automatically' {
    $broken = Join-Path $env:RUNNER_TEMP 'broken-release'
    if (Test-Path $broken) { Remove-Item $broken -Recurse -Force }
    Copy-Item $ReleaseDir $broken -Recurse
    Set-Content -LiteralPath "$broken\app\dist\main.js" -Value "console.error('broken build'); process.exit(1);" -Encoding ASCII
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$broken\scripts\update.ps1"
    $updateExit = $LASTEXITCODE
    $h = Wait-Healthy 60
    $mainJs = Get-Content "$InstallDir\app\dist\main.js" -Raw
    Write-Host "      update exit $updateExit, health $($h.status), rolled back: $($mainJs -notmatch 'broken build')"
    $updateExit -ne 0 -and $mainJs -notmatch 'broken build' -and @(Get-ChildItem $InstallDir -Directory -Filter 'app.fallida-*').Count -eq 1
}

if ($failures.Count -gt 0) {
    Write-Host "`n$($failures.Count) check(s) failed:`n  $($failures -join "`n  ")" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll Windows installation checks passed." -ForegroundColor Green
