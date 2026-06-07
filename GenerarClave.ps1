[CmdletBinding()]
param(
    [int]$Longitud = 32,
    [switch]$SinEspeciales
)

$mayusculas  = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$minusculas  = 'abcdefghijklmnopqrstuvwxyz'
$numeros     = '0123456789'
$especiales  = '!@#$%^&*()-_=+[]{}|;:,.<>?'

$universo = $mayusculas + $minusculas + $numeros
if (-not $SinEspeciales) { $universo += $especiales }

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

function Get-RandomChar([string]$chars) {
    $bytes = New-Object 'byte[]' 4
    do {
        $rng.GetBytes($bytes)
        $index = [System.BitConverter]::ToUInt32($bytes, 0) % $chars.Length
    } while ($index -ge ($chars.Length * [Math]::Floor([uint32]::MaxValue / $chars.Length)))
    return $chars[$index]
}

$clave = @(
    Get-RandomChar $mayusculas
    Get-RandomChar $minusculas
    Get-RandomChar $numeros
)
if (-not $SinEspeciales) { $clave += Get-RandomChar $especiales }

while ($clave.Count -lt $Longitud) {
    $clave += Get-RandomChar $universo
}

for ($i = $clave.Count - 1; $i -gt 0; $i--) {
    $bytes = New-Object 'byte[]' 4; $rng.GetBytes($bytes)
    $j = [System.BitConverter]::ToUInt32($bytes, 0) % ($i + 1)
    $tmp = $clave[$i]; $clave[$i] = $clave[$j]; $clave[$j] = $tmp
}

$rng.Dispose()

$resultado = -join $clave

Write-Host ""
Write-Host "  Clave generada:" -ForegroundColor Cyan
Write-Host "  $resultado" -ForegroundColor Green
Write-Host ""
Write-Host "  Longitud : $($resultado.Length) caracteres" -ForegroundColor DarkGray
Write-Host "  Entropia : ~$([Math]::Round([Math]::Log($universo.Length, 2) * $resultado.Length, 1)) bits" -ForegroundColor DarkGray
Write-Host ""

try {
    Set-Clipboard -Value $resultado -ErrorAction Stop
    Write-Host "  [Copiada al portapapeles]" -ForegroundColor Yellow
} catch {}

Write-Host ""
