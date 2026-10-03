# Shared helpers for the Warique deployment scripts.
# Compatible with Windows PowerShell 5.1 (the version that ships with Windows) and PowerShell 7.
# Saved as UTF-8 with BOM: PowerShell 5.1 reads BOM-less scripts as ANSI and breaks accents.

Set-StrictMode -Version 3.0

# Well-known SIDs: account names are translated on Spanish Windows ("Administradores")
$script:SidAdministrators = '*S-1-5-32-544'
$script:SidSystem = '*S-1-5-18'
$script:SidLocalService = '*S-1-5-19'

$script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "    OK  $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "    !!  $Message" -ForegroundColor Yellow }

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ejecuta este script en PowerShell "Como administrador".'
    }
}

function Read-PlainSecret([string]$Prompt) {
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Read-NewPassword([string]$Prompt, [int]$MinLength = 12) {
    while ($true) {
        $first = Read-PlainSecret "$Prompt (minimo $MinLength caracteres)"
        if ($first.Length -lt $MinLength) { Write-Warn "Muy corta."; continue }
        $second = Read-PlainSecret 'Repitela'
        if ($first -ne $second) { Write-Warn 'No coinciden.'; continue }
        return $first
    }
}

function New-RandomSecret([int]$Bytes = 48) {
    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($buffer)
}

# Writes UTF-8 without BOM (MySQL option files and .env must not start with a BOM)
function Write-Utf8File([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

# Replaces inherited permissions: Administrators and SYSTEM full control, plus optional grants
# such as "*S-1-5-19:(OI)(CI)RX" (LocalService read/execute).
function Set-RestrictedAcl([string]$Path, [string[]]$ExtraGrants = @()) {
    if (-not $script:OnWindows) { return }
    $isDir = Test-Path -LiteralPath $Path -PathType Container
    $inherit = if ($isDir) { '(OI)(CI)' } else { '' }
    $grants = @("$($script:SidAdministrators):$($inherit)F", "$($script:SidSystem):$($inherit)F") + $ExtraGrants
    $arguments = @($Path, '/inheritance:r')
    foreach ($grant in $grants) { $arguments += @('/grant:r', $grant) }
    $output = & icacls.exe @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls fallo en ${Path}: $output" }
}

# Quotes arguments for Start-Process (PowerShell 5.1 has no ProcessStartInfo.ArgumentList)
function ConvertTo-ArgumentString([string[]]$Arguments) {
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -eq '') { '""' }   # e.g. sc.exe ... password= ""
        elseif ($argument -match '[\s"]') {
            # Backslashes before a quote must be doubled (C runtime argument rules)
            $escaped = ($argument -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
            '"' + $escaped + '"'
        }
        else { $argument }
    }
    return ($quoted -join ' ')
}

# Runs a native program without PowerShell re-encoding its output (PowerShell 5.1 pipes
# would turn a UTF-8 dump into UTF-16). Returns @{ ExitCode; StdOut; StdErr }.
function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory = (Get-Location).Path) {
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList (ConvertTo-ArgumentString $Arguments) `
            -WorkingDirectory $WorkingDirectory -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        return @{
            ExitCode = $process.ExitCode
            StdOut   = [IO.File]::ReadAllText($outFile)
            StdErr   = [IO.File]::ReadAllText($errFile)
        }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ExePath([string]$BinDir, [string]$Name) {
    if ($script:OnWindows) { return (Join-Path $BinDir "$Name.exe") }
    return (Join-Path $BinDir $Name)
}

# MySQL option file so passwords never appear on a command line (visible to other processes)
function New-MySqlOptionFile([string]$Path, [string]$User, [string]$Password, [int]$Port = 3306) {
    $escaped = $Password.Replace('\', '\\').Replace('"', '\"')
    Write-Utf8File $Path "[client]`r`nuser=$User`r`npassword=`"$escaped`"`r`nhost=127.0.0.1`r`nport=$Port`r`n"
    Set-RestrictedAcl $Path
}

function Invoke-MySqlFile([string]$MySqlBinDir, [string]$OptionFile, [string]$SqlFile) {
    # "source" lets mysql read the file itself: no shell redirection, no re-encoding
    $sourcePath = (Resolve-Path -LiteralPath $SqlFile).Path.Replace('\', '/')
    $result = Invoke-Native (Get-ExePath $MySqlBinDir 'mysql') @(
        "--defaults-extra-file=$OptionFile", '--default-character-set=utf8mb4', "--execute=source $sourcePath")
    if ($result.ExitCode -ne 0) { throw "mysql fallo ($SqlFile): $($result.StdErr.Trim())" }
}

function Invoke-MySqlQuery([string]$MySqlBinDir, [string]$OptionFile, [string]$Query) {
    $result = Invoke-Native (Get-ExePath $MySqlBinDir 'mysql') @(
        "--defaults-extra-file=$OptionFile", '--default-character-set=utf8mb4', '--batch', '--skip-column-names', "--execute=$Query")
    if ($result.ExitCode -ne 0) { throw "mysql fallo: $($result.StdErr.Trim())" }
    return $result.StdOut.Trim()
}

function Get-DeployConfigPath([string]$InstallDir) { Join-Path $InstallDir 'config\deploy.json' }

function Get-DeployConfig([string]$InstallDir) {
    $path = Get-DeployConfigPath $InstallDir
    if (-not (Test-Path -LiteralPath $path)) { throw "No existe $path. Ejecuta primero install.ps1." }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-DeployConfig([string]$InstallDir, $Config) {
    Write-Utf8File (Get-DeployConfigPath $InstallDir) ($Config | ConvertTo-Json -Depth 5)
}

# Returns the /api/health object, or $null if the server does not answer in time
function Wait-Health([int]$Port, [int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 5
            if ($health.database -eq 'up') { return $health }
        } catch {
            # 503 while the database is down, or connection refused while starting
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $null
}

# Service name, bin folder and my.ini of the MySQL Windows service
function Get-MySqlServiceInfo([string]$ServiceName) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
    if (-not $service) { throw "No existe el servicio de MySQL '$ServiceName'." }
    $exe = if ($service.PathName -match '^"([^"]+)"') { $Matches[1] } else { ($service.PathName -split ' ')[0] }
    $ini = if ($service.PathName -match '--defaults-file="?([^"]+?)"?(\s|$)') { $Matches[1] } else { $null }
    return [pscustomobject]@{
        Name      = $service.Name
        State     = $service.State
        StartMode = $service.StartMode
        BinDir    = Split-Path $exe -Parent
        IniPath   = $ini
    }
}

function Get-LanAddresses {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -ExpandProperty IPAddress
}
