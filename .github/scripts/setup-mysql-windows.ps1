# CI only: installs MySQL 8.4 LTS as a Windows service the way the MySQL installer does
# (service with --defaults-file=my.ini), WITHOUT default-time-zone, so install.ps1 must fix it.
param(
    [Parameter(Mandatory = $true)][string]$RootPassword,
    [string]$ServiceName = 'MySQL84',
    [string]$BaseDir = 'C:\mysql84'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Other MySQL services preinstalled on the runner image would collide on port 3306
Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
    Set-Service $_.Name -StartupType Disabled
    Write-Host "Disabled preinstalled service $($_.Name)"
}

$zip = Join-Path $env:RUNNER_TEMP 'mysql.zip'
$downloaded = $null
foreach ($patch in 12..0) {
    $version = "8.4.$patch"
    foreach ($url in @(
            "https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-$version-winx64.zip",
            "https://downloads.mysql.com/archives/get/p/23/file/mysql-$version-winx64.zip")) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            $downloaded = $version
            Write-Host "Downloaded MySQL $version from $url"
            break
        } catch { }
    }
    if ($downloaded) { break }
}
if (-not $downloaded) { throw 'Could not download any MySQL 8.4.x' }

New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $BaseDir
$home84 = (Get-ChildItem -LiteralPath $BaseDir -Directory | Where-Object Name -like 'mysql-8.4*' | Select-Object -First 1).FullName
$dataDir = Join-Path $BaseDir 'data'
$ini = Join-Path $BaseDir 'my.ini'
@"
[client]
port=3306

[mysqld]
basedir=$($home84.Replace('\', '/'))
datadir=$($dataDir.Replace('\', '/'))
port=3306
"@ | Set-Content -LiteralPath $ini -Encoding ASCII

$mysqld = Join-Path $home84 'bin\mysqld.exe'
& $mysqld "--defaults-file=$ini" --initialize-insecure --console
if ($LASTEXITCODE -ne 0) { throw 'mysqld --initialize failed' }
& $mysqld --install $ServiceName "--defaults-file=$ini"
if ($LASTEXITCODE -ne 0) { throw 'mysqld --install failed' }
Start-Service $ServiceName
& (Join-Path $home84 'bin\mysql.exe') -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$RootPassword';"
if ($LASTEXITCODE -ne 0) { throw 'Could not set the root password' }
Write-Host "MySQL $downloaded running as service $ServiceName ($((Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").PathName))"
