#Requires -Version 5.1
<#
    LimpiarAutodesk.ps1
    Limpia rastros de AutoCAD, Revit o ambos segun seleccion.
    Opciones 1 y 2: borrado quirurgico (no toca el otro producto).
    Opcion 3: elimina todo Autodesk completo.
    Requiere ejecutar como Administrador para limpiar HKLM.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   LIMPIEZA AUTODESK  /  AUTOCAD  /  REVIT |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([string]$t)  { Write-Host "  >> $t" -ForegroundColor Yellow }
function Write-OK([string]$t)    { Write-Host "     OK  $t" -ForegroundColor Green }
function Write-Skip([string]$t)  { Write-Host "     --  $t" -ForegroundColor DarkGray }
function Write-Fail([string]$t)  { Write-Host "     !!  $t" -ForegroundColor Red }

function Get-FolderSizeMB([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $sz = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
           Measure-Object -Property Length -Sum).Sum
    return [Math]::Round($sz / 1MB, 1)
}

function Remove-FolderSafe([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { Write-Skip $label; return 0 }
    $mb = Get-FolderSizeMB $path
    & takeown /F "$path" /R /A /D S 2>&1 | Out-Null
    & icacls "$path" /grant "*S-1-5-32-544:F" /T /C /Q 2>&1 | Out-Null
    $empty = Join-Path $env:TEMP ("empty_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    & robocopy $empty $path /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:0 2>&1 | Out-Null
    Remove-Item $empty -Force -ErrorAction SilentlyContinue
    & cmd /c "rd /s /q `"$path`"" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path $path)) { Write-OK ("{0}  ({1} MB)" -f $label, $mb); return $mb }
    Write-Fail "Marcada para eliminar al reiniciar: $label"
    & reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations /t REG_MULTI_SZ /d "`\??\$path" /f 2>&1 | Out-Null
    return 0
}

# Borra solo subcarpetas que coincidan con el patron, deja el resto intacto
function Remove-SubfoldersByPattern([string]$parent, [string]$pattern, [string]$label) {
    if (-not (Test-Path $parent)) { Write-Skip $label; return 0 }
    $subs = Get-ChildItem $parent -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $pattern }
    if (-not $subs) { Write-Skip $label; return 0 }
    $total = 0
    foreach ($s in $subs) {
        $total += Remove-FolderSafe $s.FullName ("$label\" + $s.Name)
    }
    return $total
}

function Remove-FilesSafe([string]$dir, [string[]]$patterns, [string]$label) {
    if (-not (Test-Path $dir)) { Write-Skip $label; return 0 }
    $total = 0; $count = 0
    foreach ($pat in $patterns) {
        Get-ChildItem $dir -Filter $pat -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $total += $_.Length
            try { Remove-Item $_.FullName -Force -ErrorAction Stop; $count++ } catch {}
        }
    }
    if ($count -gt 0) { Write-OK ("{0}  ({1} archivos, {2} MB)" -f $label, $count, [Math]::Round($total/1MB,2)) }
    else { Write-Skip $label }
    return $total / 1MB
}

function Remove-RegistryKey([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { Write-Skip $label; return }
    try { Remove-Item $path -Recurse -Force -ErrorAction Stop; Write-OK $label }
    catch { Write-Fail "Sin permisos: $label" }
}

# Borra solo las subclaves que coincidan con el patron dentro de una clave padre
function Remove-RegistrySubkeysByPattern([string]$parent, [string]$pattern) {
    if (-not (Test-Path $parent)) { return }
    Get-ChildItem $parent -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $pattern } |
        ForEach-Object {
            try { Remove-Item $_.PSPath -Recurse -Force -ErrorAction Stop; Write-OK $_.PSPath }
            catch { Write-Fail "Sin permisos: $($_.PSPath)" }
        }
}

# ── Admin check ───────────────────────────────────────────────────────────────

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# ── Menu ──────────────────────────────────────────────────────────────────────

Write-Header

if (-not $esAdmin) {
    Write-Host "  ADVERTENCIA: No estas ejecutando como Administrador." -ForegroundColor Red
    Write-Host "  Las claves de registro HKLM no podran eliminarse." -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "  Que deseas limpiar?" -ForegroundColor White
Write-Host ""
Write-Host "   [1] Solo AutoCAD  (Revit no sera tocado)" -ForegroundColor Yellow
Write-Host "   [2] Solo Revit    (AutoCAD no sera tocado)" -ForegroundColor Yellow
Write-Host "   [3] Todo          (AutoCAD + Revit + Autodesk completo)" -ForegroundColor Red
Write-Host "   [4] Cancelar" -ForegroundColor DarkGray
Write-Host ""
$opcion = Read-Host "  Opcion"

switch ($opcion) {
    '1' { $limpiarAutoCAD = $true;  $limpiarRevit = $false; $limpiarTodo = $false }
    '2' { $limpiarAutoCAD = $false; $limpiarRevit = $true;  $limpiarTodo = $false }
    '3' { $limpiarAutoCAD = $true;  $limpiarRevit = $true;  $limpiarTodo = $true  }
    default { Write-Host "  Cancelado." -ForegroundColor DarkGray; exit 0 }
}

# ── Detectar instaladas y pedir confirmacion ──────────────────────────────────

$instaladas = @()
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.DisplayName -and $p.DisplayVersion) {
            if ($limpiarAutoCAD -and $p.DisplayName -like '*AutoCAD*') { $instaladas += $p.DisplayName }
            if ($limpiarRevit   -and $p.DisplayName -like '*Revit*')   { $instaladas += $p.DisplayName }
        }
    }
}

Write-Host ""
if ($instaladas.Count -gt 0) {
    Write-Host "  ATENCION: Se detectaron productos instalados:" -ForegroundColor Red
    $instaladas | Select-Object -Unique | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  Usalo solo si ya desinstalaste desde Panel de Control." -ForegroundColor Red
    Write-Host ""
    $conf = Read-Host "  Escribi CONFIRMAR para continuar de todos modos"
    if ($conf -ne 'CONFIRMAR') { Write-Host "  Cancelado." -ForegroundColor DarkGray; exit 0 }
} else {
    $conf = Read-Host "  Continuar con la limpieza? (s/n)"
    if ($conf -ne 's' -and $conf -ne 'S') { Write-Host "  Cancelado." -ForegroundColor DarkGray; exit 0 }
}

Write-Host ""
$totalMB = 0.0

# ── 0. Procesos y servicios ───────────────────────────────────────────────────

Write-Step "Deteniendo procesos"

$terminos = [System.Collections.Generic.List[string]]@('adsk','autodesk','fnplicensing','adlm','genuineservice')
if ($limpiarAutoCAD) { $terminos.AddRange([string[]]@('autocad','acad')) }
if ($limpiarRevit)   { $terminos.AddRange([string[]]@('revit','rvt')) }
$procRegex = '(?i)(' + ($terminos -join '|') + ')'

Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match $procRegex -or ($_.Path -and $_.Path -match $procRegex)
} | ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    Write-OK "Proceso detenido: $($_.Name)"
}
Start-Sleep -Seconds 2

Write-Step "Deteniendo servicios"
@('AdskLicensing','FNPLicensingService','AdskAccessServiceHost','AdskIdentityManager') | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue; Write-OK "Servicio detenido: $_"
    }
    if ($svc) { Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue }
}
Start-Sleep -Seconds 2

# ── 1. Carpetas ───────────────────────────────────────────────────────────────

$padresAutodesk = @(
    @{ P = "$env:APPDATA\Autodesk";                             L = "AppData\Roaming\Autodesk" },
    @{ P = "$env:LOCALAPPDATA\Autodesk";                        L = "AppData\Local\Autodesk" },
    @{ P = "$env:ProgramData\Autodesk";                         L = "ProgramData\Autodesk" },
    @{ P = "$env:PUBLIC\Documents\Autodesk";                    L = "Public\Documents\Autodesk" },
    @{ P = "$env:ProgramFiles\Autodesk";                        L = "Program Files\Autodesk" },
    @{ P = "${env:ProgramFiles(x86)}\Autodesk";                 L = "Program Files (x86)\Autodesk" },
    @{ P = "$env:ProgramFiles\Common Files\Autodesk Shared";    L = "Program Files\Common Files\Autodesk Shared" },
    @{ P = "${env:ProgramFiles(x86)}\Common Files\Autodesk Shared"; L = "Program Files (x86)\Common Files\Autodesk Shared" }
)

if ($limpiarTodo) {
    Write-Step "Eliminando carpetas completas de Autodesk"
    foreach ($x in $padresAutodesk) { $totalMB += Remove-FolderSafe $x.P $x.L }
} else {
    $patFolders = if ($limpiarAutoCAD) { '(?i)(autocad|acad)' } else { '(?i)(revit|rvt)' }
    Write-Step "Eliminando subcarpetas de $(if ($limpiarAutoCAD) {'AutoCAD'} else {'Revit'})"
    foreach ($x in $padresAutodesk) { $totalMB += Remove-SubfoldersByPattern $x.P $patFolders $x.L }
}

# ── 2. Archivos temporales (AutoCAD) ─────────────────────────────────────────

if ($limpiarAutoCAD) {
    Write-Step "Archivos temporales de AutoCAD"
    $totalMB += Remove-FilesSafe $env:TEMP @('*.ac$','*.sv$','*.bak','*.log') "Temporales en TEMP"
    $totalMB += Remove-FilesSafe "$env:USERPROFILE\Documents" @('*.bak','*.sv$','*.ac$') "Backups en Documentos"
}

# ── 3. Registro ───────────────────────────────────────────────────────────────

Write-Step "Registro de Windows"

if ($limpiarTodo) {
    Remove-RegistryKey "HKCU:\Software\Autodesk"                              "HKCU:\Software\Autodesk"
    Remove-RegistryKey "HKCU:\Software\FLEXlm License Manager"               "HKCU:\Software\FLEXlm License Manager"
    Remove-RegistryKey "HKLM:\SOFTWARE\Autodesk"                             "HKLM:\SOFTWARE\Autodesk"
    Remove-RegistryKey "HKLM:\SOFTWARE\WOW6432Node\Autodesk"                 "HKLM:\SOFTWARE\WOW6432Node\Autodesk"
    Remove-RegistryKey "HKLM:\SOFTWARE\FLEXlm License Manager"               "HKLM:\SOFTWARE\FLEXlm License Manager"
    Remove-RegistryKey "HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager"   "HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager"
} else {
    $patReg = if ($limpiarAutoCAD) { '(?i)(autocad|acad)' } else { '(?i)(revit|rvt)' }
    foreach ($root in @('HKCU:\Software\Autodesk','HKLM:\SOFTWARE\Autodesk','HKLM:\SOFTWARE\WOW6432Node\Autodesk')) {
        Remove-RegistrySubkeysByPattern $root $patReg
    }
}

# ── Resumen ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  +============================================+" -ForegroundColor Cyan
Write-Host ("  |   Limpieza completada. {0,6} MB liberados   |" -f [Math]::Round($totalMB, 1)) -ForegroundColor Green
Write-Host "  +============================================+" -ForegroundColor Cyan
Write-Host ""

if (-not $esAdmin) {
    Write-Host "  Para eliminar claves HKLM, ejecuta como Administrador." -ForegroundColor Yellow
    Write-Host ""
}

Read-Host "  Presiona ENTER para cerrar"
