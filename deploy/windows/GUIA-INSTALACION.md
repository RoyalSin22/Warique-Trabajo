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
      instante **y suene**, cobro en efectivo y por Yape, y que aparezcan en *Cierre*. Con el volumen
      del celular o tablet de cocina **al máximo**, y del celular de cada mozo audible.

**Al día siguiente**

- [ ] **6. Respaldo:** la tarjeta de arriba en *Cierre* está **verde** (el respaldo de las 19:30 se hizo,
      se copió a la carpeta de Drive y Google Drive estaba abierto para subirlo). Si sale roja, revisa
      la sección 5 antes de seguir. Entra también a <https://drive.google.com> → *RespaldosWarique* y
      confirma que está el archivo de anoche.

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
      con la sesión del dueño abierta (bloqueada con Win+L, no cerrada). Si la PC se reinicia (corte de
      luz, Windows Update) y nadie inicia sesión, Warique sigue funcionando pero Drive no: el respaldo
      queda en la PC y la tarjeta de *Cierre* se pone **roja** con «Google Drive NO estaba abierto».
6. **Horario:** el local atiende de **11:00 a 18:00**. El instalador ya viene configurado para ese
   horario: Windows Update no reinicia la PC entre las 08:00 y las 22:00, y el respaldo diario corre a
   las **19:30**, después del cierre de caja (a más tardar 19:00), para que incluya el arqueo y los
   gastos del día. Si la PC se apaga antes, el respaldo se hace apenas se vuelva a encender.

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

Parámetros útiles: `-ActiveHoursStart 8 -ActiveHoursEnd 22 -BackupTime '19:30'` si cambia el horario,
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
- **Agregar platos a un pedido:** mientras la cocina lo tiene (*Pendiente* o *En preparación*), en el
  detalle del pedido toca *Agregar platos a este pedido* (ícono de lista con +): los platos nuevos se
  suman al **mismo** pedido y la cocina los ve marcados **AGREGADO**, con timbre. Si el pedido ya está
  *Listo* o *Entregado*, el botón cambia a *Otro pedido para esta mesa* (la mesa ya queda elegida).
- **Quitar un plato** (se acabó, el cliente ya no lo quiere): en el detalle del pedido toca ⊖ junto al
  plato, elige cuántas unidades y escribe el motivo. Mientras el pedido está *Pendiente* lo puede hacer
  el mozo; **cuando la cocina ya empezó, solo el dueño**. El plato queda tachado con su motivo, el total
  baja y la cocina recibe un aviso «NO preparar». No se puede quitar el único plato (en ese caso se
  cancela el pedido) ni dejar el total por debajo de lo ya cobrado (primero se anula el cobro).
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
- **Cobro mal registrado** (era Yape y se marcó efectivo, monto equivocado, otra mesa): solo el dueño
  lo corrige. Abre el pedido (desde la lista de pedidos o tocando el pago en *Pagos del día*), toca la
  flecha ↶ junto al cobro y escribe el motivo. El cobro queda **tachado** con su motivo, deja de contar
  en la caja, en los reportes y en el CSV de ventas, y el pedido vuelve a quedar **por cobrar**: el mozo
  registra el cobro correcto. Si el pedido se debe cancelar, primero anula sus cobros.
- **Caja cerrada:** después de *Cerrar caja* el sistema **no acepta** cobros ni gastos en efectivo de
  ese día (Yape y Plin sí), para que el arqueo no cambie a escondidas. Si faltó registrar algo, el
  dueño toca *Reabrir caja* en la tarjeta del arqueo, registra lo que faltaba y vuelve a cerrar.
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
- **Respaldo:** la tarjeta de arriba en *Cierre* sale **verde** si el respaldo de anoche se hizo, se
  copió a la carpeta de Drive y Google Drive estaba abierto para subirlo; si sale **roja**, avisa a
  soporte ese mismo día. **Una vez por semana** entra a <https://drive.google.com> → *RespaldosWarique*
  y mira que el archivo más reciente sea de anoche: es la única prueba de que de verdad está en la nube.
- **Sonidos:** la cocina escucha un timbre con cada pedido nuevo, que se **repite cada 30 segundos**
  hasta que alguien toque *Empezar*, y un zumbido si se cancela un pedido que tenía en cola. El mozo
  que tomó el pedido escucha otro timbre (y el celular vibra) cuando la cocina lo marca *Listo*.
  En el navegador, la primera vez que se abre la pantalla de cocina aparece *Activar*: tócalo una vez
  (los navegadores no dejan sonar una página que nadie tocó). Mientras la pantalla de cocina esté
  abierta, la tablet **no se apaga sola**; déjala enchufada.
- **Personal:** en *Gestión → Usuarios* creas las cuentas de mozos y cocina, restableces claves y
  desactivas a quien ya no trabaja (su sesión se cierra al instante). **Si alguien pierde el
  celular**, restablécele la clave: todas sus sesiones abiertas se cierran en ese momento. Lo mismo
  pasa cuando alguien cambia su propia clave (en ese celular sigue conectado).
- **Tablet que queda encendida de noche:** al día siguiente se actualiza sola con los pedidos del día;
  si su sesión venció, pide ingresar de nuevo apenas se desbloquea la pantalla.
- **La PC debe quedar encendida** durante la atención. Si se reinicia, Warique vuelve solo en
  1 o 2 minutos; los celulares se reconectan solos (punto verde arriba a la derecha).
- **Punto rojo "Sin conexión"** en los celulares: revisa que la PC esté encendida y en el Wi-Fi.

## 5. Respaldos

- Todos los días a la hora configurada se crea `C:\Warique\backups\warique-AAAAMMDD-HHMMSS-diario.zip`
  y se copia a la carpeta externa. Si la PC estaba apagada, se hace apenas se encienda.
- Respaldo manual (antes de algo riesgoso): `C:\Warique\scripts\backup.ps1 -Tag manual`
- **Prueba de restauración una vez al mes**: es la única forma de saber que los respaldos sirven.
  La forma segura, en la misma PC y **antes de abrir** (por ejemplo a las 10:00, cuando no hubo
  movimiento desde el respaldo de las 19:30):
  1. En *Cierre*, mira las ventas de ayer y anótalas.
  2. Ejecuta `C:\Warique\scripts\restore.ps1` con el respaldo **diario de anoche** (ver abajo).
  3. Entra a la app: *Cierre* de ayer debe mostrar las mismas ventas. Si es así, el respaldo sirve.
  4. Si algo no cuadra, restaura el archivo `…-antes-de-restaurar.zip` que el script creó y avisa a
     soporte.

### Restaurar

Reemplaza **todos** los datos actuales por los del respaldo: borra la base y la carga desde el
archivo, así que no se mezcla nada del estado actual. Antes guarda una copia del estado actual con la
etiqueta `antes-de-restaurar`, y si el respaldo es de una versión anterior aplica después los cambios
de base de datos que le faltan:

```powershell
C:\Warique\scripts\restore.ps1 -BackupFile 'C:\Warique\backups\warique-20261003-193000-diario.zip'
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
| "Error del servidor" al iniciar sesión | MySQL detenido | Se reinicia solo en 10–60 s; si no, `status.ps1` e iniciar **MySQL84 y luego Warique** (si MySQL se detiene, Windows también detiene Warique) |
| "No se aceptan movimientos en efectivo" | La caja de ese día ya se cerró | El dueño toca *Reabrir caja*, registra y vuelve a cerrar |
| "Tu sesión ya no es válida" | Le cambiaron o restablecieron la clave | Ingresar con la clave nueva |
| Las horas del reporte están corridas 5 h | MySQL no está en UTC | `default-time-zone='+00:00'` en `my.ini` y reiniciar MySQL |
| "Último respaldo FALLÓ" | Disco lleno | `C:\Warique\logs\backup.log` |
| Tarjeta roja "NO se copió" | Google Drive cerrado sesión, sin espacio o en modo «Transmitir» | Abrir Google Drive, revisar modo «Duplicar archivos» |
| Tarjeta roja "Google Drive NO estaba abierto" | La PC se reinició y nadie inició sesión en Windows | Iniciar sesión con la cuenta del dueño; Drive sube lo pendiente solo |
| La cocina no suena | Volumen bajo/silencio, o en el navegador falta tocar *Activar* | Subir el volumen; abrir *Cocina* y tocar *Activar* |
| La tablet de cocina se apaga | Otra app en primer plano o batería en ahorro extremo | Dejar abierta la pantalla de cocina y la tablet enchufada |
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
