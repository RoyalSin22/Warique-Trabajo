<#
.SYNOPSIS
  Crea la llave propia para firmar el APK de Warique (una sola vez, en la PC de quien compila).
.DESCRIPTION
  Android solo deja actualizar una app si la version nueva esta firmada con la MISMA llave. Si se
  pierde la llave, para actualizar hay que desinstalar la app en cada celular. Por eso este script:
    1. Genera la llave (PKCS12, RSA 2048, valida ~27 anos) con una clave aleatoria larga, fuera del
       repositorio: por defecto en %USERPROFILE%\WariqueLlaves\warique.jks.
    2. Escribe app\android\key.properties (ignorado por git) para que build-release.ps1 -WithApk firme
       con ella.
    3. Deja junto a la llave LEEME-respaldo.txt con la clave y la huella SHA-256.
  Nunca reemplaza una llave existente. La clave no aparece en la linea de comandos (keytool la lee de
  una variable de entorno).
  Despues: copia la carpeta de la llave a DOS lugares seguros (USB guardado + gestor de claves o la
  cuenta de Google del dueno) y no la subas nunca al repositorio.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File deploy\windows\new-android-key.ps1
#>
[CmdletBinding()]
param(
    [string]$KeyDir = (Join-Path $HOME 'WariqueLlaves'),
    [string]$Alias = 'warique',
    # Nombre que aparece dentro del certificado (no es secreto)
    [string]$Owner = 'Warique'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$keyStore = Join-Path $KeyDir 'warique.jks'
$readme = Join-Path $KeyDir 'LEEME-respaldo.txt'
$keyProperties = Join-Path $repo 'app\android\key.properties'

function Find-Keytool {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe'; $candidates += Join-Path $env:JAVA_HOME 'bin/keytool' }
    $onPath = Get-Command keytool -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    # The JDK that Android Studio bundles (Flutter uses it to build the APK)
    foreach ($root in @($env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($root) { $candidates += Join-Path $root 'Android\Android Studio\jbr\bin\keytool.exe' }
    }
    $found = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $found) { throw 'No se encontro keytool. Instala Android Studio (trae Java) o un JDK 17+ y define JAVA_HOME.' }
    return $found
}

if (Test-Path -LiteralPath $keyStore) {
    throw "Ya existe $keyStore. No se reemplaza: una llave nueva impediria actualizar la app en los celulares."
}
if (Test-Path -LiteralPath $keyProperties) {
    throw "Ya existe $keyProperties (apunta a otra llave). Revisalo antes de crear una nueva."
}
& git -C $repo check-ignore -q 'app/android/key.properties' 2>$null
if ($LASTEXITCODE -ne 0) { throw 'app/android/key.properties no esta ignorado por git: no se escribe una clave que podria subirse.' }

$keytool = Find-Keytool
Write-Step 'Creando la llave de firma del APK'
New-Item -ItemType Directory -Force -Path $KeyDir | Out-Null

# Letters and digits only: safe in key.properties (a Java properties file) and easy to copy by hand
$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })

# PKCS12 uses one password for the store and the key. keytool reads it from the environment.
$env:WARIQUE_KEY_PASSWORD = $password
try {
    $result = Invoke-Native $keytool @(
        '-genkeypair', '-noprompt', '-keystore', $keyStore, '-storetype', 'PKCS12', '-alias', $Alias,
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
        '-dname', "CN=$Owner, O=$Owner, C=PE",
        '-storepass:env', 'WARIQUE_KEY_PASSWORD', '-keypass:env', 'WARIQUE_KEY_PASSWORD')
    if ($result.ExitCode -ne 0) { throw "keytool fallo: $($result.StdErr.Trim()) $($result.StdOut.Trim())" }
    $list = Invoke-Native $keytool @('-list', '-v', '-keystore', $keyStore, '-alias', $Alias, '-storepass:env', 'WARIQUE_KEY_PASSWORD')
    if ($list.ExitCode -ne 0) { throw "keytool no pudo leer la llave creada: $($list.StdErr.Trim())" }
} finally {
    Remove-Item Env:WARIQUE_KEY_PASSWORD -ErrorAction SilentlyContinue
}
$fingerprint = ([regex]::Match($list.StdOut, 'SHA256:\s*([0-9A-F:]+)')).Groups[1].Value
Write-Ok "Llave creada: $keyStore"

# Forward slashes: key.properties is read by Gradle (Java), where a backslash is an escape character
$storePath = (Resolve-Path -LiteralPath $keyStore).Path.Replace('\', '/')
Write-Utf8File $keyProperties ("storeFile=$storePath`nstorePassword=$password`nkeyAlias=$Alias`nkeyPassword=$password`n")
Write-Ok "Configuracion para compilar: $keyProperties (ignorado por git)"

Write-Utf8File $readme (@(
        'LLAVE DE FIRMA DEL APK DE WARIQUE - GUARDAR EN LUGAR SEGURO',
        '',
        'Sin esta llave no se puede actualizar la app de Android en los celulares: habria que',
        'desinstalarla y volver a instalarla en cada uno. Guarda esta carpeta (warique.jks + este archivo)',
        'en DOS lugares: un USB guardado y un gestor de claves o la cuenta de Google del dueno.',
        'Nunca la subas al repositorio ni la envies por chat.',
        '',
        "Archivo:        warique.jks (PKCS12)",
        "Alias:          $Alias",
        "Clave:          $password",
        "Huella SHA-256: $fingerprint",
        "Creada:         $((Get-Date).ToString('yyyy-MM-dd HH:mm'))",
        '',
        'Para compilar en otra PC, crea app\android\key.properties con:',
        '  storeFile=C:/ruta/a/warique.jks',
        "  storePassword=$password",
        "  keyAlias=$Alias",
        "  keyPassword=$password"
    ) -join "`r`n")
Write-Ok "Respaldo con la clave y la huella: $readme"

Write-Host "`nHuella SHA-256 del certificado:`n    $fingerprint" -ForegroundColor White
Write-Warn 'Copia ahora la carpeta de la llave a un USB y a un segundo lugar seguro.'
Write-Host "Luego compila el APK firmado: powershell -ExecutionPolicy Bypass -File deploy\windows\build-release.ps1 -WithApk" -ForegroundColor Green
