# Warique: instalación y operación en la PC del local

Guía para quien instala y da soporte. La sección **Operación diaria** es para el dueño.

## Cómo queda instalado

```
Celulares / tablets (Wi-Fi del local)
        │  http://192.168.x.x:3000   (app web + API + tiempo real, un solo puerto)
        ▼
PC del local (Windows 10/11)
  ├─ Servicio "Warique"  → Node.js, cuenta LocalService, arranca solo y se reinicia ante fallos
  ├─ Servicio "MySQL84"  → solo acepta conexiones de la misma PC (bind-address=127.0.0.1)
  └─ Tarea "Warique - Respaldo diario" → C:\Warique\backups + copia en Google Drive del dueño
```

| Carpeta | Contenido | Quién puede leerla |
|---|---|---|
| `C:\Warique\app` | Aplicación (se reemplaza en cada actualización) | Administradores, servicio |
| `C:\Warique\app.previous` | Versión anterior, para volver atrás | Administradores, servicio |
| `C:\Warique\config` | `.env` (secretos), `backup.cnf`, `deploy.json` | Solo administradores (el servicio lee `.env`) |
| `C:\Warique\logs` | Registros del servicio y de los respaldos | Administradores, servicio |
| `C:\Warique\backups` | Respaldos `.zip` de los últimos 30 días | Solo administradores |
| `C:\Warique\scripts` | `backup.ps1`, `restore.ps1`, `status.ps1`, `update.ps1` | Administradores |

## 1. Antes de instalar

1. **Windows 10 u 11 actualizado**, con una cuenta de administrador.
2. **Node.js 22 LTS** desde <https://nodejs.org> (instalador `.msi`, opciones por defecto).
3. **MySQL 8.4 LTS** desde <https://dev.mysql.com/downloads/installer/>:
   - Tipo *Server only*, configurado **como servicio de Windows** que inicia con el sistema.
   - Anota la clave de `root`; el instalador de Warique la pide una vez y no la guarda.
   - Desmarca *Open Windows Firewall port for network access*: MySQL no debe verse desde la red.
   - No uses MySQL 8.0: dejó de recibir parches de seguridad en abril de 2026.
4. **IP fija para la PC** (recomendado: *reserva DHCP* en el router). El instalador muestra la
   dirección MAC; en el router busca "DHCP", "Reserva de dirección" o "IP estática" y asígnale
   siempre la misma IP. Así los celulares no pierden la conexión cuando se reinicia el router.
5. **Google Drive para la copia externa** (queda fuera del local si roban o se daña la PC):
   1. Instala **Google Drive para escritorio** (<https://www.google.com/drive/download/>) e inicia sesión
      con la cuenta de Google del dueño.
   2. En el ícono de Drive → ⚙ *Preferencias* → *Mi unidad*, elige **«Duplicar archivos»**
      (*Mirror files*). **No** uses «Transmitir archivos» (*Stream files*): en ese modo Drive solo crea
      una unidad virtual `G:` dentro de la sesión del dueño, que la tarea de respaldo (cuenta SYSTEM)
      no puede ver. Con «Duplicar archivos» aparece la carpeta `C:\Users\<dueño>\Mi unidad`
      (o `My Drive`).
   3. Activa la **verificación en dos pasos** de esa cuenta de Google: los respaldos contienen las ventas
      y las claves cifradas del personal.
   4. Drive sube los archivos **solo mientras la sesión de Windows del dueño está iniciada**. Deja la PC
      con la sesión del dueño abierta (bloqueada con Win+L, no cerrada).
6. **Horario:** el local atiende de **11:00 a 18:00**. El instalador ya viene configurado para ese
   horario: Windows Update no reinicia la PC entre las 08:00 y las 22:00, y el respaldo diario corre a
   las 18:30. Si la PC se apaga antes, el respaldo se hace apenas se vuelva a encender.

## 2. Instalar

En la máquina de desarrollo: `deploy\windows\build-release.ps1 -WithApk` genera
`release\warique-<versión>.zip` y su `.sha256`. Copia el `.zip` a la PC del local, descomprímelo y,
en **PowerShell como administrador** dentro de esa carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -GoogleDrive
```

`-GoogleDrive` busca la carpeta `Mi unidad` / `My Drive` y crea dentro `RespaldosWarique` (si hay
varias cuentas en la PC, pregunta cuál). Para otro destino usa `-BackupCopyDir 'E:\Respaldos'`.

El instalador pregunta antes de cambiar `my.ini` o el tipo de red, pide la clave de `root` de MySQL
y los datos de la cuenta del dueño. Al final muestra la dirección para los celulares, por ejemplo
`http://192.168.1.50:3000`, y **ejecuta la tarea de respaldo tal como correrá cada noche** (cuenta
SYSTEM), para comprobar que de verdad llega a Google Drive. Después revisa en
<https://drive.google.com> que aparezca la carpeta `RespaldosWarique` con un archivo `.zip`.

Parámetros útiles: `-ActiveHoursStart 8 -ActiveHoursEnd 22 -BackupTime '18:30'` si cambia el horario,
`-MySqlService MySQL84` si hay más de un MySQL, `-Port 3000`,
`-RetentionDays 30`, `-SkipWindowsSettings` si la PC la administra otra persona.

## 3. Celulares y tablets

- **Lo más fácil:** en la PC (o en el celular del dueño) entra a *Gestión → Conectar celulares* y
  escanea el código QR con la cámara de cada celular.
- **Navegador (recomendado para empezar):** abre `http://192.168.1.50:3000` en Chrome y usa
  *Agregar a pantalla principal*. Se actualiza solo cuando se actualiza el servidor.
- **App Android:** si el paquete se armó con `-WithApk`, descárgala desde
  `http://192.168.1.50:3000/descargas/warique.apk` (activa *Instalar apps desconocidas* para Chrome).
  La primera vez pide la dirección del servidor.
- Los celulares deben estar en el **mismo Wi-Fi** que la PC. Usa una red para el personal
  distinta a la de los clientes.

## 4. Operación diaria (dueño)

- **Al abrir:** en *Gestión → Menú*, toca el botón de *Habilitar todos* (flecha circular) para quitar
  los agotados del día anterior.
- **Segunda ronda en una mesa:** un pedido enviado a cocina no se edita; en el detalle del pedido
  toca el carrito (*Otro pedido para esta mesa*) y la mesa ya queda elegida.
- **Si se corta el Wi-Fi al enviar:** vuelve a tocar *Enviar a cocina* sin cambiar nada; el sistema
  reconoce el reintento y **no duplica** el pedido ni el pago.
- **Al cerrar:** en la pestaña *Cierre* revisa ventas, cobrado y por cobrar. En *Pagos del día* filtra
  por Yape o Plin y compara cada N.° de operación con tu app del banco (el botón copia el número).
- **Respaldo:** la tarjeta de arriba en *Cierre* sale **verde** si el respaldo de anoche se hizo y se
  copió fuera de la PC; si sale **roja**, avisa a soporte ese mismo día.
- **Personal:** en *Gestión → Usuarios* creas las cuentas de mozos y cocina, restableces claves y
  desactivas a quien ya no trabaja (su sesión se cierra al instante).
- **La PC debe quedar encendida** durante la atención. Si se reinicia, Warique vuelve solo en
  1 o 2 minutos; los celulares se reconectan solos (punto verde arriba a la derecha).
- **Punto rojo "Sin conexión"** en los celulares: revisa que la PC esté encendida y en el Wi-Fi.

## 5. Respaldos

- Todos los días a la hora configurada se crea `C:\Warique\backups\warique-AAAAMMDD-HHMMSS-diario.zip`
  y se copia a la carpeta externa. Si la PC estaba apagada, se hace apenas se encienda.
- Respaldo manual (antes de algo riesgoso): `C:\Warique\scripts\backup.ps1 -Tag manual`
- **Prueba de restauración una vez al mes**: es la única forma de saber que los respaldos sirven.
  Hazla en otra PC con MySQL o fuera del horario de atención.

### Restaurar

Reemplaza **todos** los datos actuales por los del respaldo (antes guarda una copia del estado
actual con la etiqueta `antes-de-restaurar`):

```powershell
C:\Warique\scripts\restore.ps1 -BackupFile 'C:\Warique\backups\warique-20261003-233000-diario.zip'
```

## 6. Actualizar a una versión nueva

Descomprime el paquete nuevo y, como administrador, desde esa carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update.ps1
```

Hace un respaldo, reemplaza la aplicación y verifica que responda. Si la versión nueva no arranca,
**vuelve sola a la anterior**. Hazlo fuera del horario de atención.

## 7. Diagnóstico

```powershell
powershell -ExecutionPolicy Bypass -File C:\Warique\scripts\status.ps1
```

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Los celulares no abren la página | PC apagada, otro Wi-Fi, IP cambió, red "Pública" | `status.ps1`; revisar la reserva DHCP; marcar la red como Privada |
| "Error del servidor" al iniciar sesión | MySQL detenido | `status.ps1`; iniciar el servicio MySQL84 |
| Las horas del reporte están corridas 5 h | MySQL no está en UTC | `default-time-zone='+00:00'` en `my.ini` y reiniciar MySQL |
| "Último respaldo FALLÓ" | Disco lleno | `C:\Warique\logs\backup.log` |
| Tarjeta roja "NO se copió" | Google Drive cerrado sesión, sin espacio o en modo «Transmitir» | Abrir Google Drive, revisar modo «Duplicar archivos» |
| Los `.zip` no aparecen en drive.google.com | La sesión de Windows del dueño estaba cerrada | Iniciar sesión; Drive sube lo pendiente solo |
| El servicio se reinicia solo | Error de la aplicación | `C:\Warique\logs\warique.err.log` |

Registros: `C:\Warique\logs\warique.out.log` y `warique.err.log` (rotan cada 10 MB, se guardan 8),
`warique.wrapper.log` (arranques y paradas) y `backup.log`.

## 8. Desinstalar

```powershell
Stop-Service warique; C:\Warique\service\warique.exe uninstall
Unregister-ScheduledTask -TaskName 'Warique - Respaldo diario' -Confirm:$false
Remove-NetFirewallRule -Name 'Warique-HTTP'
```

La base de datos y `C:\Warique\backups` se conservan; bórralos a mano solo si estás seguro.

## Seguridad: lo que cubre y lo que no

- El servicio corre con **LocalService** (sin acceso a los archivos del dueño). MySQL solo escucha
  en la misma PC. El usuario de la app **no puede borrar** registros ni cambiar tablas.
- Las claves de MySQL de la app y del respaldo son aleatorias y solo las leen administradores.
- **No cubre:** el tráfico va sin cifrar (HTTP) dentro del Wi-Fi del local; quien esté en esa red
  podría verlo. Por eso el Wi-Fi del personal debe tener clave propia y no ser el de los clientes.
- Si la PC la usa también el dueño para otras cosas: cuenta de Windows **sin** permisos de
  administrador para el uso diario, y antivirus activo.
