#Requires -Version 5.1
<#
    LimpiarAutodesk.ps1
    Elimina todos los rastros de Autodesk/AutoCAD tras la desinstalacion:
    archivos temporales, carpetas de datos y entradas de registro.
    Requiere ejecutar como Administrador para limpiar HKLM.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     LIMPIEZA AUTODESK / AUTOCAD         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([string]$texto) {
    Write-Host "  >> $texto" -ForegroundColor Yellow
}

function Write-OK([string]$texto) {
    Write-Host "     OK  $texto" -ForegroundColor Green
}

function Write-Skip([string]$texto) {
    Write-Host "     --  $texto" -ForegroundColor DarkGray
}

function Write-Fail([string]$texto) {
    Write-Host "     !!  $texto" -ForegroundColor Red
}

function Get-FolderSizeMB([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    return [Math]::Round($size / 1MB, 1)
}

function Remove-FolderSafe([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { Write-Skip $label; return 0 }
    $mb = Get-FolderSizeMB $path
    try {
        Remove-Item $path -Recurse -Force -ErrorAction Stop
        Write-OK ("{0}  ({1} MB)" -f $label, $mb)
        return $mb
    } catch {
        Write-Fail "No se pudo eliminar: $label"
        return 0
    }
}

function Remove-FilesSafe([string]$directory, [string[]]$patterns, [string]$label) {
    if (-not (Test-Path $directory)) { Write-Skip $label; return 0 }
    $total = 0
    $count = 0
    foreach ($pattern in $patterns) {
        $files = Get-ChildItem $directory -Filter $pattern -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $total += $file.Length
            try { Remove-Item $file.FullName -Force -ErrorAction Stop; $count++ } catch {}
        }
    }
    if ($count -gt 0) {
        Write-OK ("{0}  ({1} archivos, {2} MB)" -f $label, $count, [Math]::Round($total / 1MB, 2))
    } else {
        Write-Skip $label
    }
    return $total / 1MB
}

function Remove-RegistryKey([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { Write-Skip $label; return }
    try {
        Remove-Item $path -Recurse -Force -ErrorAction Stop
        Write-OK $label
    } catch {
        Write-Fail "Sin permisos para: $label  (ejecuta como Administrador)"
    }
}

# ── Verificar si es admin ─────────────────────────────────────────────────────

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# ── Inicio ────────────────────────────────────────────────────────────────────

Write-Header

if (-not $esAdmin) {
    Write-Host "  ADVERTENCIA: No estas ejecutando como Administrador." -ForegroundColor Red
    Write-Host "  Las claves de registro en HKLM no podran eliminarse." -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "  Este script eliminara:" -ForegroundColor White
Write-Host "   - Carpetas de Autodesk en AppData, ProgramData y Program Files" -ForegroundColor DarkGray
Write-Host "   - Archivos temporales de AutoCAD (.bak, .sv`$, .ac`$, .log)" -ForegroundColor DarkGray
Write-Host "   - Entradas de registro de Autodesk" -ForegroundColor DarkGray
Write-Host ""
$confirm = Read-Host "  Continuar? (s/n)"
if ($confirm -ne 's' -and $confirm -ne 'S') {
    Write-Host "  Cancelado." -ForegroundColor DarkGray; exit 0
}

Write-Host ""
$totalMB = 0.0

# ── 1. Carpetas en AppData ────────────────────────────────────────────────────

Write-Step "Carpetas en AppData\Roaming"
$totalMB += Remove-FolderSafe "$env:APPDATA\Autodesk"                              "AppData\Roaming\Autodesk"

Write-Step "Carpetas en AppData\Local"
$totalMB += Remove-FolderSafe "$env:LOCALAPPDATA\Autodesk"                         "AppData\Local\Autodesk"

Write-Step "Carpetas en ProgramData"
$totalMB += Remove-FolderSafe "$env:ProgramData\Autodesk"                          "ProgramData\Autodesk"

Write-Step "Carpetas en Public\Documents"
$totalMB += Remove-FolderSafe "$env:PUBLIC\Documents\Autodesk"                     "Public\Documents\Autodesk"

Write-Step "Carpetas en Program Files"
$totalMB += Remove-FolderSafe "$env:ProgramFiles\Autodesk"                         "Program Files\Autodesk"
$totalMB += Remove-FolderSafe "$env:ProgramFiles\Common Files\Autodesk Shared"     "Program Files\Common Files\Autodesk Shared"

Write-Step "Carpetas en Program Files (x86)"
$totalMB += Remove-FolderSafe "${env:ProgramFiles(x86)}\Autodesk"                  "Program Files (x86)\Autodesk"
$totalMB += Remove-FolderSafe "${env:ProgramFiles(x86)}\Common Files\Autodesk Shared" "Program Files (x86)\Common Files\Autodesk Shared"

# ── 2. Archivos temporales ────────────────────────────────────────────────────

Write-Step "Archivos temporales de AutoCAD en TEMP"
$totalMB += Remove-FilesSafe $env:TEMP @('*.ac$', '*.sv$', '*.bak', '*.log') "Temporales AutoCAD en TEMP"

Write-Step "Archivos de respaldo en Documentos"
$totalMB += Remove-FilesSafe "$env:USERPROFILE\Documents" @('*.bak', '*.sv$', '*.ac$') "Backups en Documentos"

Write-Step "Logs de AutoCAD en Documentos"
$totalMB += Remove-FilesSafe "$env:USERPROFILE\Documents" @('*.log') "Logs en Documentos"

# ── 3. Registro de Windows ────────────────────────────────────────────────────

Write-Step "Registro HKCU (usuario actual)"
Remove-RegistryKey "HKCU:\Software\Autodesk"                       "HKCU:\Software\Autodesk"
Remove-RegistryKey "HKCU:\Software\FLEXlm License Manager"         "HKCU:\Software\FLEXlm License Manager"

Write-Step "Registro HKLM (requiere Administrador)"
Remove-RegistryKey "HKLM:\SOFTWARE\Autodesk"                       "HKLM:\SOFTWARE\Autodesk"
Remove-RegistryKey "HKLM:\SOFTWARE\WOW6432Node\Autodesk"           "HKLM:\SOFTWARE\WOW6432Node\Autodesk"
Remove-RegistryKey "HKLM:\SOFTWARE\FLEXlm License Manager"         "HKLM:\SOFTWARE\FLEXlm License Manager"
Remove-RegistryKey "HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager" "HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager"

# ── Resumen ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ("  |  Limpieza completada. {0,6} MB liberados  |" -f [Math]::Round($totalMB, 1)) -ForegroundColor Green
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

if (-not $esAdmin) {
    Write-Host "  Para eliminar las claves HKLM, vuelve a ejecutar" -ForegroundColor Yellow
    Write-Host "  el script como Administrador (clic derecho -> Ejecutar como administrador)." -ForegroundColor DarkGray
    Write-Host ""
}

Read-Host "  Presiona ENTER para cerrar"
