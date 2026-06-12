#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   DIAGNOSTICO INSTALACION AUTOCAD       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK   ([string]$t) { Write-Host ("  [OK]  {0}" -f $t) -ForegroundColor Green }
function Write-Warn ([string]$t) { Write-Host ("  [!!]  {0}" -f $t) -ForegroundColor Yellow }
function Write-Fail ([string]$t) { Write-Host ("  [XX]  {0}" -f $t) -ForegroundColor Red }
function Write-Info ([string]$t) { Write-Host ("  [--]  {0}" -f $t) -ForegroundColor DarkGray }
function Write-Section ([string]$t) {
    Write-Host ""
    Write-Host "  ── $t " -ForegroundColor Cyan
}

Write-Header

# ── 1. Reinicio pendiente ─────────────────────────────────────────────────────

Write-Section "Reinicio pendiente"

$pendingKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
)

$rebootPending = $false
if (Test-Path $pendingKeys[0]) { Write-Fail "Windows Update requiere reinicio"; $rebootPending = $true }
if (Test-Path $pendingKeys[1]) { Write-Fail "Component Based Servicing requiere reinicio"; $rebootPending = $true }

$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
if ($pfro) { Write-Warn "Hay operaciones de archivo pendientes al reiniciar ($($pfro.Count) entradas)"; $rebootPending = $true }

if (-not $rebootPending) { Write-OK "No hay reinicios pendientes" }

# ── 2. Espacio en disco ───────────────────────────────────────────────────────

Write-Section "Espacio en disco"

$disco = Get-PSDrive C
$libreGB = [Math]::Round($disco.Free / 1GB, 1)
$totalGB = [Math]::Round(($disco.Used + $disco.Free) / 1GB, 1)

if ($libreGB -lt 10) {
    Write-Fail ("Disco C: {0} GB libres de {1} GB -AutoCAD necesita minimo 10 GB" -f $libreGB, $totalGB)
} elseif ($libreGB -lt 20) {
    Write-Warn ("Disco C: {0} GB libres de {1} GB -justo, recomendado 20 GB+" -f $libreGB, $totalGB)
} else {
    Write-OK ("Disco C: {0} GB libres de {1} GB" -f $libreGB, $totalGB)
}

# ── 3. .NET Framework ─────────────────────────────────────────────────────────

Write-Section ".NET Framework"

$dotnet = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if ($dotnet) {
    $release = $dotnet.Release
    $version = switch ($release) {
        { $_ -ge 533320 } { "4.8.1+" }
        { $_ -ge 528040 } { "4.8" }
        { $_ -ge 461808 } { "4.7.2" }
        { $_ -ge 461308 } { "4.7.1" }
        default { "4.x (Release: $release)" }
    }
    if ($release -ge 528040) {
        Write-OK (".NET Framework $version instalado")
    } else {
        Write-Fail (".NET Framework $version -AutoCAD necesita 4.8 o superior")
    }
} else {
    Write-Fail ".NET Framework 4.x no encontrado"
}

# .NET 6/7/8 (para versiones recientes de AutoCAD)
$dotnetNew = & dotnet --list-runtimes 2>$null
if ($dotnetNew) {
    $dotnetNew | Where-Object { $_ -match 'WindowsDesktop' } | ForEach-Object {
        Write-OK (".NET Runtime: $_")
    }
} else {
    Write-Warn ".NET 6/7/8 no detectado (puede ser necesario para AutoCAD 2027)"
}

# ── 4. Visual C++ Redistributables ───────────────────────────────────────────

Write-Section "Visual C++ Redistributables"

$vcKeys = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'; Nombre = 'VC++ 2015-2022 x64' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'; Nombre = 'VC++ 2015-2022 x86' },
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'; Nombre = 'VC++ 2015-2022 x64 (WOW)' },
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'; Nombre = 'VC++ 2015-2022 x86 (WOW)' }
)

$vcFaltante = $false
foreach ($vc in $vcKeys) {
    if (Test-Path $vc.Path) {
        $ver = (Get-ItemProperty $vc.Path -ErrorAction SilentlyContinue).Version
        Write-OK ("{0}: {1}" -f $vc.Nombre, $ver)
    } else {
        Write-Fail ("{0}: NO instalado" -f $vc.Nombre)
        $vcFaltante = $true
    }
}

# ── 5. Windows Installer ──────────────────────────────────────────────────────

Write-Section "Servicio Windows Installer"

$msi = Get-Service 'msiserver' -ErrorAction SilentlyContinue
if ($msi) {
    Write-OK ("Windows Installer: {0}" -f $msi.Status)
} else {
    Write-Fail "Servicio Windows Installer no encontrado"
}

# ── 6. DirectX ────────────────────────────────────────────────────────────────

Write-Section "DirectX"

$dx = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction SilentlyContinue
if ($dx) {
    Write-OK ("DirectX Version: {0}" -f $dx.Version)
} else {
    Write-Warn "No se pudo leer la version de DirectX"
}

# ── 7. Restos de Autodesk en registro ─────────────────────────────────────────

Write-Section "Restos de Autodesk en registro"

$regPaths = @(
    'HKLM:\SOFTWARE\Autodesk',
    'HKLM:\SOFTWARE\WOW6432Node\Autodesk',
    'HKCU:\Software\Autodesk'
)
$restos = $false
foreach ($r in $regPaths) {
    if (Test-Path $r) {
        Write-Warn ("Resto encontrado: {0}" -f $r)
        $restos = $true
    }
}
if (-not $restos) { Write-OK "No hay restos de Autodesk en el registro" }

# ── 8. Errores recientes del instalador en Event Log ─────────────────────────

Write-Section "Errores recientes de instalacion (Event Log)"

$eventos = Get-EventLog -LogName Application -Source 'MsiInstaller' -EntryType Error -Newest 5 -ErrorAction SilentlyContinue
if ($eventos) {
    foreach ($e in $eventos) {
        Write-Warn ("{0}  {1}" -f $e.TimeGenerated.ToString('yyyy-MM-dd HH:mm'), $e.Message.Substring(0, [Math]::Min(80, $e.Message.Length)))
    }
} else {
    Write-OK "Sin errores recientes del instalador MSI"
}

# ── Resumen y recomendaciones ─────────────────────────────────────────────────

Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |            RECOMENDACIONES              |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

if ($rebootPending) {
    Write-Host "  1. Reinicia el PC antes de intentar instalar." -ForegroundColor Yellow
}
if ($vcFaltante) {
    Write-Host "  2. Instala Visual C++ Redistributable 2015-2022:" -ForegroundColor Yellow
    Write-Host "     https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor DarkGray
}
if ($libreGB -lt 10) {
    Write-Host "  3. Libera espacio en disco C: (minimo 10 GB libres)." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "  Presiona ENTER para cerrar"
