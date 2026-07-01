# scripts

Colección de scripts PowerShell de utilidad para Windows: gestión de
contraseñas locales, generación de claves y mantenimiento de instalaciones
de Autodesk (AutoCAD / Revit).

Todos requieren **PowerShell 5.1+** y se ejecutan directamente, sin
dependencias externas.

## `Boveda.ps1` — Gestor de contraseñas local cifrado

Bóveda de contraseñas en un único archivo cifrado, protegida por PIN +
contraseña maestra.

- Cifrado AES-256-CBC + autenticación HMAC-SHA256 (esquema Encrypt-then-MAC).
- Derivación de claves con PBKDF2 (310.000 iteraciones, SHA-256).
- Acceso protegido por PIN de 4 dígitos con **autodestrucción de la bóveda**
  tras 3 intentos fallidos (sobrescribe el archivo con bytes aleatorios).
- Menú interactivo: buscar/copiar clave, listar servicios, guardar clave
  (manual o generada), eliminar entrada, cambiar contraseña maestra.
- Copiado al portapapeles en vez de mostrar la clave en pantalla cuando es
  posible.

### Configuración inicial (requerida antes del primer uso)

El script exige un archivo `pin.hash` en la misma carpeta que la bóveda
(por defecto `%USERPROFILE%\.boveda\pin.hash`) — **no se genera solo**,
hay que crearlo una vez:

```powershell
$pin = "1234"   # tu PIN de 4 dígitos
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pin)))
New-Item -ItemType Directory -Path "$env:USERPROFILE\.boveda" -Force | Out-Null
Set-Content "$env:USERPROFILE\.boveda\pin.hash" $hash -NoNewline
```

### Uso

```powershell
.\Boveda.ps1                              # usa la ruta por defecto
.\Boveda.ps1 -VaultPath "D:\vault.enc"    # ruta alternativa
```

La primera vez que corre (si no existe `vault.enc`) pide crear una
contraseña maestra; en corridas siguientes la pide para desbloquear.

**Advertencia:** no hay forma de recuperar la bóveda si se pierde la
contraseña maestra, ni si se agotan los 3 intentos de PIN — ambos casos
son irreversibles por diseño.

## `GenerarClave.ps1` — Generador de contraseñas aleatorias

Genera una contraseña aleatoria criptográficamente segura (usa
`RandomNumberGenerator`, no `Get-Random`) y la copia al portapapeles.

```powershell
.\GenerarClave.ps1                    # 32 caracteres, con símbolos
.\GenerarClave.ps1 -Longitud 16
.\GenerarClave.ps1 -SinEspeciales     # solo letras y números
```

## `DiagnosticoAutodesk.ps1` — Diagnóstico previo a instalación

Revisa, **sin modificar nada**, las condiciones típicas que hacen fallar
una instalación de AutoCAD: reinicio pendiente, espacio en disco, versión
de .NET Framework/.NET runtime, Visual C++ Redistributables, servicio
Windows Installer, versión de DirectX, restos de Autodesk en el registro y
errores recientes del instalador en el Event Log. Termina con una lista de
recomendaciones según lo encontrado.

```powershell
.\DiagnosticoAutodesk.ps1
```

No requiere permisos de administrador para el diagnóstico (algunas
lecturas de registro pueden salir vacías sin ellos).

## `LimpiarAutodesk.ps1` — Limpieza de restos de Autodesk

Elimina carpetas, claves de registro, accesos directos y entradas de
desinstalación de AutoCAD y/o Revit que quedan tras una desinstalación
incompleta. Pensado para dejar el sistema listo antes de una reinstalación
limpia.

```powershell
.\LimpiarAutodesk.ps1
```

Menú interactivo:
1. Solo AutoCAD (no toca Revit)
2. Solo Revit (no toca AutoCAD)
3. Todo Autodesk (carpetas y claves compartidas incluidas)
4. Cancelar

**Requiere ejecutarse como Administrador** para poder borrar claves
`HKLM`; sin permisos elevados, esas quedan sin tocar y el script lo
informa al final.

**Advertencia:** es una herramienta destructiva. Detecta instalaciones
activas de AutoCAD/Revit antes de proceder y pide confirmación explícita
(escribir `CONFIRMAR`) si encuentra alguna — úsalo solo después de
desinstalar desde el Panel de Control, no como sustituto del
desinstalador.

## Estado de verificación

Todos los scripts pasan validación de sintaxis
(`[System.Management.Automation.Language.Parser]::ParseFile`).
Ejecución real verificada para `GenerarClave.ps1` y
`DiagnosticoAutodesk.ps1` (no destructivos). `Boveda.ps1` y
`LimpiarAutodesk.ps1` no se ejecutaron de punta a punta: el primero es
interactivo y requiere una terminal real (no funciona con input
redirigido en modo no interactivo); el segundo modifica el sistema
(archivos y registro) y no corresponde probarlo destructivamente.

Nota menor: en algunas consolas, los caracteres de línea (`──`) en los
encabezados de `DiagnosticoAutodesk.ps1` pueden verse corruptos si la
consola no está en codificación UTF-8 — es un problema de encoding de
consola, no del script.
