#Requires -Version 5.1
param([string]$VaultPath = "$env:USERPROFILE\.boveda\vault.enc")

Set-StrictMode -Off

# PIN fijo — almacenado como hash SHA-256, no puede cambiarse
$PIN_HASH = '+/auC84+sYJW0iAFvRzJleY542THi6VY7BSi56RAm68='

# ── Criptografia ─────────────────────────────────────────────────────────────

function Get-DerivedKeys {
    param([string]$password, [byte[]]$salt)
    $rfc = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        [System.Text.Encoding]::UTF8.GetBytes($password),
        $salt, 310000,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $material = $rfc.GetBytes(64)
    $rfc.Dispose()
    $encKey = [byte[]]($material[0..31])
    $macKey = [byte[]]($material[32..63])
    return @{ Enc = $encKey; Mac = $macKey }
}

function Protect-Data {
    param([hashtable]$keys, [string]$plaintext)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = [byte[]]$keys['Enc']
    $aes.GenerateIV()
    $iv = $aes.IV
    $enc = $aes.CreateEncryptor()
    $plain = [System.Text.Encoding]::UTF8.GetBytes($plaintext)
    $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length)
    $enc.Dispose(); $aes.Dispose()
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$keys['Mac'])
    $mac = $hmac.ComputeHash($iv + $cipher)
    $hmac.Dispose()
    return @{
        iv     = [Convert]::ToBase64String($iv)
        cipher = [Convert]::ToBase64String($cipher)
        mac    = [Convert]::ToBase64String($mac)
    }
}

function Unprotect-Data {
    param([hashtable]$keys, [string]$ivB64, [string]$cipherB64, [string]$macB64)
    $iv     = [Convert]::FromBase64String($ivB64)
    $cipher = [Convert]::FromBase64String($cipherB64)
    $mac    = [Convert]::FromBase64String($macB64)
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$keys['Mac'])
    $expected = $hmac.ComputeHash($iv + $cipher)
    $hmac.Dispose()
    $diff = 0
    for ($i = 0; $i -lt $mac.Length; $i++) { $diff = $diff -bor ($mac[$i] -bxor $expected[$i]) }
    if ($diff -ne 0) { throw "Contrasena incorrecta o boveda corrupta." }
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = [byte[]]$keys['Enc']
    $aes.IV = $iv
    $dec = $aes.CreateDecryptor()
    $plainBytes = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
    $dec.Dispose(); $aes.Dispose()
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

# ── Generador ────────────────────────────────────────────────────────────────

function New-RandomKey {
    param([int]$length = 32)
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $digits  = '0123456789'
    $special = '!@#$%^&*()-_=+[]{}|;:,.<>?'
    $uni     = $upper + $lower + $digits + $special
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    function Pick([string]$s) {
        $b = New-Object 'byte[]' 4
        do { $rng.GetBytes($b); $idx = [BitConverter]::ToUInt32($b, 0) % $s.Length } `
           while ($idx -ge ($s.Length * [Math]::Floor([uint32]::MaxValue / $s.Length)))
        return $s[$idx]
    }
    $chars = [System.Collections.Generic.List[char]]@(
        (Pick $upper), (Pick $lower), (Pick $digits), (Pick $special)
    )
    while ($chars.Count -lt $length) { $chars.Add((Pick $uni)) }
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $b = New-Object 'byte[]' 4; $rng.GetBytes($b)
        $j = [BitConverter]::ToUInt32($b, 0) % ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    $rng.Dispose()
    return -join $chars
}

# ── Persistencia ─────────────────────────────────────────────────────────────

function Read-Vault {
    param([string]$password)
    $raw  = Get-Content $VaultPath -Raw | ConvertFrom-Json
    $salt = [Convert]::FromBase64String($raw.salt)
    $keys = Get-DerivedKeys $password $salt
    $json = Unprotect-Data $keys $raw.iv $raw.cipher $raw.mac
    $list = New-Object System.Collections.Generic.List[object]
    $parsed = $json | ConvertFrom-Json
    if ($parsed -ne $null) {
        foreach ($item in $parsed) { $list.Add($item) }
    }
    return $keys, $list, $salt
}

function Write-Vault {
    param([hashtable]$keys, [System.Collections.Generic.List[object]]$entries, [byte[]]$salt)
    $dir = Split-Path $VaultPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = if ($entries.Count -eq 0) { '[]' } else { $entries | ConvertTo-Json -Depth 3 }
    $blob = Protect-Data $keys $json
    [ordered]@{
        version = 1
        salt    = [Convert]::ToBase64String($salt)
        iv      = $blob['iv']
        cipher  = $blob['cipher']
        mac     = $blob['mac']
    } | ConvertTo-Json | Set-Content $VaultPath -Encoding UTF8
}

function New-Vault {
    param([string]$password)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object 'byte[]' 32; $rng.GetBytes($salt); $rng.Dispose()
    $keys = Get-DerivedKeys $password $salt
    $entries = New-Object System.Collections.Generic.List[object]
    Write-Vault $keys $entries $salt
    return $keys, $entries, $salt
}

# ── Control de PIN y bloqueo ─────────────────────────────────────────────────

function Get-AttemptCount {
    $dir = Split-Path $VaultPath
    $f   = Join-Path $dir 'attempts.dat'
    if (-not (Test-Path $f)) { return 0 }
    return [int]([string](Get-Content $f -Raw)).Trim()
}

function Set-AttemptCount {
    param([int]$count)
    $dir = Split-Path $VaultPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content (Join-Path $dir 'attempts.dat') $count -Encoding UTF8
}

function Test-Pin {
    param([string]$pin)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($pin)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hash  = [Convert]::ToBase64String($sha.ComputeHash($bytes))
    $sha.Dispose()
    return $hash -eq $PIN_HASH
}

function Invoke-Corruption {
    if (Test-Path $VaultPath) {
        $rng     = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $garbage = New-Object 'byte[]' 8192
        $rng.GetBytes($garbage); $rng.Dispose()
        [System.IO.File]::WriteAllBytes($VaultPath, $garbage)
    }
    Set-AttemptCount 99
}

# ── UI ────────────────────────────────────────────────────────────────────────

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +=================================+" -ForegroundColor Cyan
    Write-Host "  |       BOVEDA DE CLAVES          |" -ForegroundColor Cyan
    Write-Host "  +=================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Read-SecurePlain {
    param([string]$prompt)
    $ss = Read-Host $prompt -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}

function Set-Clipboard-Safe {
    param([string]$text)
    try { Set-Clipboard -Value $text; return $true } catch { return $false }
}

function Wait-Enter {
    Write-Host ""; Read-Host "  Presiona ENTER para continuar" | Out-Null
}

# ── Opciones del menu ─────────────────────────────────────────────────────────

function Invoke-Search {
    param([System.Collections.Generic.List[object]]$entries)
    Show-Header
    Write-Host "  BUSCAR CLAVE" -ForegroundColor Cyan
    Write-Host ""
    $term = Read-Host "  Servicio a buscar"
    $found = @($entries | Where-Object { $_.servicio -like "*$term*" })
    if ($found.Count -eq 0) {
        Write-Host "  No se encontraron resultados." -ForegroundColor Red
        Wait-Enter; return
    }
    $entry = $null
    if ($found.Count -eq 1) {
        $entry = $found[0]
    } else {
        Write-Host ""
        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $found[$i].servicio, $found[$i].usuario) -ForegroundColor White
        }
        Write-Host ""
        $sel = [int](Read-Host "  Selecciona numero")
        if ($sel -lt 1 -or $sel -gt $found.Count) {
            Write-Host "  Seleccion invalida." -ForegroundColor Red; Wait-Enter; return
        }
        $entry = $found[$sel - 1]
    }
    Write-Host ""
    Write-Host ("  Servicio : {0}" -f $entry.servicio) -ForegroundColor White
    Write-Host ("  Usuario  : {0}" -f $entry.usuario)  -ForegroundColor White
    Write-Host ""
    if (Set-Clipboard-Safe $entry.clave) {
        Write-Host "  Clave copiada al portapapeles." -ForegroundColor Green
    } else {
        Write-Host ("  Clave: {0}" -f $entry.clave) -ForegroundColor Yellow
    }
    Wait-Enter
}

function Show-All {
    param([System.Collections.Generic.List[object]]$entries)
    Show-Header
    Write-Host "  TODOS LOS SERVICIOS" -ForegroundColor Cyan
    Write-Host ""
    if ($entries.Count -eq 0) {
        Write-Host "  (La boveda esta vacia)" -ForegroundColor DarkGray
    } else {
        $i = 1
        foreach ($e in $entries) {
            Write-Host ("  {0,2}. {1}" -f $i, $e.servicio) -ForegroundColor White
            Write-Host ("      Usuario : {0}" -f $e.usuario) -ForegroundColor DarkGray
            Write-Host ("      Creado  : {0}" -f $e.creado)  -ForegroundColor DarkGray
            Write-Host ""
            $i++
        }
    }
    Wait-Enter
}

function Add-Entry {
    param(
        [System.Collections.Generic.List[object]]$entries,
        [hashtable]$keys,
        [byte[]]$salt,
        [bool]$generate = $false
    )
    Show-Header
    $titulo = if ($generate) { "GENERAR Y GUARDAR CLAVE" } else { "GUARDAR NUEVA CLAVE" }
    Write-Host ("  {0}" -f $titulo) -ForegroundColor Cyan
    Write-Host ""
    $servicio = Read-Host "  Servicio (ej: Gmail, Netflix)"
    if ([string]::IsNullOrWhiteSpace($servicio)) {
        Write-Host "  El servicio no puede estar vacio." -ForegroundColor Red
        Wait-Enter; return
    }
    $usuario = Read-Host "  Usuario o email"
    if ($generate) {
        $clave = New-RandomKey 32
        Write-Host ""
        Write-Host ("  Clave generada: {0}" -f $clave) -ForegroundColor Green
    } else {
        $clave = Read-SecurePlain "  Clave"
        if ([string]::IsNullOrWhiteSpace($clave)) {
            Write-Host "  La clave no puede estar vacia." -ForegroundColor Red
            Wait-Enter; return
        }
    }
    $entry = [PSCustomObject]@{
        id       = [System.Guid]::NewGuid().ToString()
        servicio = $servicio
        usuario  = $usuario
        clave    = $clave
        creado   = (Get-Date -Format 'yyyy-MM-dd')
    }
    $entries.Add($entry)
    Write-Vault $keys $entries $salt
    Write-Host ""
    Write-Host "  Entrada guardada." -ForegroundColor Green
    if ($generate) { Set-Clipboard-Safe $clave | Out-Null; Write-Host "  Clave copiada al portapapeles." -ForegroundColor Yellow }
    Wait-Enter
}

function Remove-Entry {
    param(
        [System.Collections.Generic.List[object]]$entries,
        [hashtable]$keys,
        [byte[]]$salt
    )
    Show-Header
    Write-Host "  ELIMINAR ENTRADA" -ForegroundColor Cyan
    Write-Host ""
    if ($entries.Count -eq 0) {
        Write-Host "  La boveda esta vacia." -ForegroundColor DarkGray
        Wait-Enter; return
    }
    for ($i = 0; $i -lt $entries.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $entries[$i].servicio, $entries[$i].usuario) -ForegroundColor White
    }
    Write-Host ""
    $sel = [int](Read-Host "  Numero a eliminar (0 para cancelar)")
    if ($sel -eq 0) { return }
    if ($sel -lt 1 -or $sel -gt $entries.Count) {
        Write-Host "  Seleccion invalida." -ForegroundColor Red; Wait-Enter; return
    }
    $nombre = $entries[$sel - 1].servicio
    $confirm = Read-Host ("  Confirma eliminar '{0}' (s/n)" -f $nombre)
    if ($confirm -ne 's' -and $confirm -ne 'S') {
        Write-Host "  Cancelado." -ForegroundColor DarkGray; Wait-Enter; return
    }
    $entries.RemoveAt($sel - 1)
    Write-Vault $keys $entries $salt
    Write-Host "  Entrada eliminada." -ForegroundColor Green
    Wait-Enter
}

function Change-Password {
    param(
        [System.Collections.Generic.List[object]]$entries,
        [ref]$keysRef,
        [ref]$saltRef
    )
    Show-Header
    Write-Host "  CAMBIAR CONTRASENA MAESTRA" -ForegroundColor Cyan
    Write-Host ""
    $nueva    = Read-SecurePlain "  Nueva contrasena maestra"
    $confirma = Read-SecurePlain "  Confirma la nueva contrasena"
    if ($nueva -ne $confirma) {
        Write-Host "  Las contrasenas no coinciden." -ForegroundColor Red
        Wait-Enter; return
    }
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $newSalt = New-Object 'byte[]' 32; $rng.GetBytes($newSalt); $rng.Dispose()
    $newKeys = Get-DerivedKeys $nueva $newSalt
    Write-Vault $newKeys $entries $newSalt
    $keysRef.Value = $newKeys
    $saltRef.Value = $newSalt
    Write-Host "  Contrasena maestra actualizada." -ForegroundColor Green
    Wait-Enter
}

# ── Inicio ────────────────────────────────────────────────────────────────────

Show-Header

# -- Bloqueo permanente --------------------------------------------------------
$failCount = Get-AttemptCount
if ($failCount -ge 99) {
    Write-Host "  ACCESO BLOQUEADO PERMANENTEMENTE" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Se agotaron los intentos de PIN permitidos." -ForegroundColor DarkGray
    Write-Host "  La boveda fue destruida de forma irrecuperable." -ForegroundColor DarkGray
    Write-Host ""
    Start-Sleep 3; exit 1
}

# -- Verificacion de PIN -------------------------------------------------------
$intentosUsados = $failCount
$pinInput = Read-Host "  PIN de acceso"

if (-not (Test-Pin $pinInput)) {
    $intentosUsados++
    Set-AttemptCount $intentosUsados
    $restantes = 3 - $intentosUsados
    Write-Host ""
    if ($restantes -le 0) {
        Write-Host "  PIN incorrecto. Limite alcanzado." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Destruyendo boveda..." -ForegroundColor Red
        Invoke-Corruption
        Write-Host "  BOVEDA DESTRUIDA PERMANENTEMENTE." -ForegroundColor Red
        Write-Host ""
        Start-Sleep 4; exit 1
    }
    Write-Host ("  PIN incorrecto. Intentos restantes: {0}" -f $restantes) -ForegroundColor Red
    Write-Host ""
    Start-Sleep 2; exit 1
}

Set-AttemptCount 0
Write-Host ""

$gKeys    = $null
$gEntries = $null
$gSalt    = $null

if (-not (Test-Path $VaultPath)) {
    Write-Host "  Primera vez: crea tu contrasena maestra." -ForegroundColor Yellow
    Write-Host "  Esta contrasena protege todas tus claves. No la pierdas." -ForegroundColor DarkGray
    Write-Host ""
    $p1 = Read-SecurePlain "  Contrasena maestra"
    $p2 = Read-SecurePlain "  Confirma la contrasena"
    if ($p1 -ne $p2) {
        Write-Host "  Las contrasenas no coinciden." -ForegroundColor Red; exit 1
    }
    $gKeys, $gEntries, $gSalt = New-Vault $p1
    Write-Host ""
    Write-Host ("  Boveda creada en: {0}" -f $VaultPath) -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    $pass = Read-SecurePlain "  Contrasena maestra"
    try {
        $gKeys, $gEntries, $gSalt = Read-Vault $pass
    } catch {
        Write-Host ""
        Write-Host ("  ERROR: {0}" -f $_) -ForegroundColor Red
        exit 1
    }
}

# ── Menu ──────────────────────────────────────────────────────────────────────

$running = $true
while ($running) {
    Show-Header
    Write-Host ("  Entradas guardadas: {0}" -f $gEntries.Count) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Buscar y copiar clave"     -ForegroundColor White
    Write-Host "  [2] Ver todos los servicios"    -ForegroundColor White
    Write-Host "  [3] Guardar nueva clave"        -ForegroundColor White
    Write-Host "  [4] Generar y guardar clave"    -ForegroundColor White
    Write-Host "  [5] Eliminar entrada"           -ForegroundColor White
    Write-Host "  [6] Cambiar contrasena maestra" -ForegroundColor White
    Write-Host "  [0] Salir"                      -ForegroundColor DarkGray
    Write-Host ""
    $opt = Read-Host "  Opcion"
    switch ($opt) {
        '1' { Invoke-Search  $gEntries }
        '2' { Show-All       $gEntries }
        '3' { Add-Entry      $gEntries $gKeys $gSalt $false }
        '4' { Add-Entry      $gEntries $gKeys $gSalt $true  }
        '5' { Remove-Entry   $gEntries $gKeys $gSalt }
        '6' { Change-Password $gEntries ([ref]$gKeys) ([ref]$gSalt) }
        '0' { $running = $false }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red; Start-Sleep 1 }
    }
}

Write-Host ""
Write-Host "  Hasta luego." -ForegroundColor DarkGray
Write-Host ""
