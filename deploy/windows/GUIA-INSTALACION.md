# Warique: instalación y operación en la PC del local

Guía para quien instala y da soporte. La sección **Operación diaria** es para el dueño.

## Cómo queda instalado

```
Celulares / tablets (Wi-Fi del local)
        │  http://192.168.x.x:3000   (app web + API + tiempo real, un solo puerto)
        ▼
PC del local (Windows 10/11)
  ├─ Servicio "Warique"  → Node.js incluido, cuenta LocalService, arranca solo y se reinicia ante fallos
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

## Puesta en marcha: lista de verificación

Imprime esta lista y marca cada paso. Hazla un día **sin atención** (o antes de las 11:00): la
instalación y la carga inicial toman unas 2 a 3 horas.

**Día de instalación**

- [ ] **1. IP fija.** Reserva DHCP para la PC en el router (sección 1, punto 4). Anota la IP: `__________`
- [ ] **2. Google Drive.** Instalado en modo *Duplicar archivos*, verificación en dos pasos activada
      (sección 1, punto 5).
- [ ] **3. Instalar Warique** con `Warique-Setup-<versión>.exe` (sección 2). Al terminar, en
      <https://drive.google.com> aparece `RespaldosWarique` con un `.zip`.
      Si ya había una versión instalada, usa `update.ps1` (sección 6).
- [ ] Ejecuta `C:\Warique\scripts\status.ps1`: debe terminar con **Todo en orden**.
- [ ] **4. Datos iniciales** (en este orden, desde la PC o el celular del dueño):
  - [ ] *Gestión → Menú*: categorías (Entradas, Fondos, Bebidas…) y platos con su precio.
  - [ ] *Gestión → Mesas*: una por mesa física, con el mismo nombre que usa el personal.
  - [ ] *Gestión → Usuarios*: una cuenta por mozo y por cocinero, **cada uno con su propia clave**
        (no compartan cuentas: el cierre muestra quién cobró cada pago).
  - [ ] *Gestión → Conectar celulares*: escanea el QR con cada celular (sección 3). Para empezar usa
        el **navegador**, no el APK.
- [ ] **5. Insumos:** en *Gestión → Insumos* crea los que se compran a diario con su mínimo
      (ej.: pescado 3 kg, limón 2 kg). Luego la cocina, en su pestaña *Insumos*, registra un
      **conteo** de cada uno: ese es el stock inicial.
- [ ] Prueba completa con el personal: un pedido de mesa y uno para llevar, que la cocina los vea al
      instante, cobro en efectivo y por Yape, y que aparezcan en *Cierre*.

**Al día siguiente**

- [ ] **6. Respaldo:** la tarjeta de arriba en *Cierre* está **verde** (el respaldo de las 18:30 se hizo
      y se copió a Drive). Si sale roja, revisa la sección 5 antes de seguir.

**Primeros días de atención: marcha blanca**

- [ ] **7.** Durante **2 días de atención** usa Warique **y** la comanda en papel a la vez. Al cierre de
      cada día compara:
  - Número de pedidos y total de ventas en *Cierre* contra el papel.
  - *Pagos del día* filtrado por Yape/Plin contra la app del banco.
  - El **arqueo**: abre la caja con el fondo al empezar y ciérrala contando el efectivo.
- [ ] Deja el papel cuando se cumplan **las tres** condiciones en 2 cierres seguidos: ningún pedido
      perdido ni duplicado, ventas iguales al papel, y arqueo que cuadra (o con una diferencia que
      tiene explicación).
- [ ] Si algo no cuadra, anota la hora, el pedido y la pantalla, y ejecuta `status.ps1`: con eso
      soporte puede revisar.

## 1. Antes de instalar

1. **Windows 10 u 11 actualizado**, con una cuenta de administrador.
2. **Node.js:** no hace falta instalarlo; Warique trae su propia copia (Node.js 22 LTS).
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

### Con el instalador (recomendado)

Copia `Warique-Setup-<versión>.exe` a la PC del local (por USB o descargado del CI) y ábrelo con
doble clic. Windows pedirá permiso de administrador.

- **"Windows protegió su PC" / "Editor desconocido":** el instalador todavía no tiene firma digital.
  Toca *Más información* → *Ejecutar de todas formas*. Antes, si quieres comprobar que el archivo es
  el original, compara su SHA256 con el del archivo `.sha256` que lo acompaña:
  `Get-FileHash .\Warique-Setup-<versión>.exe` en PowerShell.
- El asistente pide la **clave de root de MySQL** y crea la **cuenta del dueño**. Luego ofrece copiar
  los respaldos a **Google Drive** y marcar la red como **Privada**; deja ambas opciones marcadas si
  la PC está en la red del local.
- Se abre una ventana negra que muestra el avance (unos minutos). Al terminar, el asistente muestra
  las direcciones para los celulares y deja abrir Warique en el navegador.
- Si algo falla, el asistente lo dice y ofrece abrir el registro
  (`C:\ProgramData\WariqueInstalador\resultado.log`). Corrige lo indicado y vuelve a ejecutarlo.

### Con PowerShell (alternativa)

En la máquina de desarrollo: `deploy\windows\build-release.ps1 -WithApk` genera
`release\warique-<versión>.zip` y su `.sha256` (con `-WithInstaller`, en Windows con Inno Setup 6,
también el `.exe`). Copia el `.zip` a la PC del local, descomprímelo y, en **PowerShell como
administrador** dentro de esa carpeta:

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
- **App Android:** primero crea la llave propia de firma **una sola vez**, en la PC donde se compila:
  `deploy\windows\new-android-key.ps1`. Guarda la carpeta `WariqueLlaves` (llave + `LEEME-respaldo.txt`)
  en un USB y en un segundo lugar seguro: sin ella, cada actualización obliga a desinstalar la app en
  todos los celulares. Si el paquete se armó con `-WithApk`, descárgala desde
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
- **Caja (arqueo):** al abrir, en *Cierre* toca *Abrir caja* e ingresa el fondo de cambio. Al cerrar,
  cuenta el efectivo **sin mirar** cuánto debería haber y toca *Cerrar caja*: el sistema muestra
  *Cuadra*, *Faltan S/ …* o *Sobran S/ …*. Si después entra otro cobro o gasto en efectivo, la tarjeta
  avisa y puedes *Volver a contar*.
- **Compra del mercado con dinero de la caja:** el fondo es lo que hay en la caja **antes** de sacar
  el dinero para el mercado. Abre la caja con ese monto y registra la compra en *Gastos* eligiendo
  **Caja**: el sistema ya la resta. Si abres la caja con lo que quedó **después** de comprar, la compra
  se restaría dos veces y el cierre mostraría un *Sobran* falso.
- **Gastos:** en *Gestión → Gastos* (o tocando *Gastos* en *Cierre*) registra cada gasto el mismo día.
  Elige **Caja** si el dinero salió de la caja (baja lo que debe haber al cerrar) u **Otro** si pagaste
  con Yape, transferencia o de tu bolsillo. Una compra del mercado se registra como *Insumos* con una
  línea por insumo (cantidad y precio pagado): el stock sube solo. Un gasto mal registrado no se borra:
  tócalo y anúlalo indicando el motivo.
- **Aviso de stock bajo:** un numerito rojo en la pestaña *Insumos* (cocina) y en *Gestión* (dueño)
  indica cuántos insumos están en su mínimo o por debajo.
- **Insumos:** en *Gestión → Insumos* creas los insumos con su mínimo (ej.: avisar cuando queden 3 kg
  de pescado). La cocina, en su pestaña *Insumos*, registra **conteos** (lo que hay realmente),
  **mermas** (lo que se malogró) y **usos**. Arriba aparece la lista *Por comprar*. Vender un plato
  **no** descuenta insumos: hacer un conteo al cierre mantiene el stock real.
- **Para el contador:** en *Cierre* toca el botón de descarga (flecha hacia abajo), elige el periodo
  (por defecto el mes anterior) y descarga: *Ventas por día*, *Pagos*, *Gastos* y *Arqueos de caja*.
  Son archivos CSV que se abren con Excel o Google Sheets; en el celular quedan en *Descargas*.
- **Ventas − gastos** en *Cierre* y *Estadísticas* es lo que entró menos lo que salió; no es la
  utilidad contable (una compra grande cuenta completa el día que se paga).
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

Ejecuta el `Warique-Setup-<versión>.exe` nuevo: detecta que Warique ya está instalado y actualiza
(solo pide la clave de root de MySQL). Con PowerShell: descomprime el paquete nuevo y, como
administrador, desde esa carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update.ps1
```

Hace un respaldo, aplica los cambios pendientes de la base de datos, reemplaza la aplicación y
verifica que responda. Si la versión nueva no arranca, **vuelve sola a la anterior**. Hazlo fuera del
horario de atención.

Si la versión trae cambios de base de datos (carpeta `database\migrations`), pedirá la **clave de
root de MySQL** (la misma de la instalación); si no hay cambios, no la pide. Los cambios solo agregan
tablas o columnas, así que la versión anterior sigue funcionando si hubiera que volver a ella.

Si la actualización se interrumpe (corte de luz), `status.ps1` lo detecta y muestra
*Cambios de base de datos SIN aplicar*: vuelve a ejecutar `update.ps1` desde el mismo paquete.

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
