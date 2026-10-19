# Warique Orders

Order, kitchen and payment management system for a small restaurant (warique), version **0.4.0**
(app 1.3.0). Runs on one Windows PC inside the restaurant; waiters, kitchen and owner use phones
and tablets over the local Wi-Fi (browser or Android app). No internet is needed to operate.

- **Owner's guide (Spanish):** [deploy/windows/GUIA-INSTALACION.md](deploy/windows/GUIA-INSTALACION.md):
  installation, daily operation, backups, troubleshooting.
- **This file:** architecture, API and the rules the code enforces, for whoever maintains it.

## Structure

```
warique-orders/
├── database/
│   ├── schema.sql        # Source of truth (MySQL 8.4 LTS; 8.0.16+ works)
│   ├── migrations/       # NNN_name.sql: later schema changes, applied by install/update
│   ├── app-user.sql      # Least-privilege DB user (no DELETE, no DDL)
│   └── backup-user.sql   # Read-only user for mysqldump
├── deploy/windows/       # Release build, install, update, backup, restore, status (PowerShell 5.1+)
│   └── GUIA-INSTALACION.md   # Installation and operations runbook (Spanish)
├── backend/              # NestJS 11 + Prisma 6 (client only) + Socket.IO
│   └── src/
│       ├── auth/         # JWT login, guards, own password change
│       ├── users/        # Staff accounts (OWNER only)
│       ├── menu/         # Categories and dishes, sold-out toggle
│       ├── tables/       # Dining tables
│       ├── orders/       # Orders, status machine, add/remove dishes, payments and their voids
│       ├── reports/      # Daily cash closing and the sales/expenses dashboard
│       ├── supplies/     # Supplies with stock: counts, waste, use (every change is a movement)
│       ├── expenses/     # Expenses; a supply purchase adds stock in the same transaction
│       ├── cash/         # Daily cash count (arqueo): change fund, expected vs counted
│       ├── realtime/     # Socket.IO gateway (rooms per role and per user)
│       ├── health/       # GET /api/health (database + MySQL time zone check)
│       ├── cli/          # create-owner: first OWNER account from a production build
│       └── common/       # Filters, DTO helpers, idempotency, money/quantity and date utils
├── app/                  # Flutter 3.44+ (Android + web), Riverpod 3, Socket.IO client
    └── lib/
        ├── core/         # HTTP client, error translation, Money (cents), Quantity (thousandths), alerts
        ├── models/       # Order, Dish, User + client copy of the status machine
        ├── data/         # Repositories, Socket.IO client, saved server/token
        ├── state/        # Riverpod providers: session, today's orders, menu, reports, inventory
        └── ui/           # login, waiter/, kitchen/, owner/, inventory/, widgets/
└── .github/
    ├── workflows/verify.yml          # CI: real Windows install + signed Android APK
    └── scripts/verify-windows-install.ps1
```

## Backend setup (Windows)

Requirements: Node.js 22 LTS, MySQL 8.4 LTS (8.0 reached end of life in April 2026).
For the restaurant PC use the scripted install in [Deployment](#deployment-windows); the steps below
are for a development machine.

1. In `my.ini` (usually `C:\ProgramData\MySQL\MySQL Server 8.x\my.ini`), under `[mysqld]`, add
   `default-time-zone='+00:00'` and restart the MySQL service. Prisma reads `DATETIME` as UTC,
   so the database defaults must be UTC too. The API converts to Peru time (UTC-5) itself.
2. Create the database and the app user:
   ```powershell
   mysql -u root -p < database\schema.sql
   # Later schema changes, in name order (the installer records them in schema_migrations)
   Get-ChildItem database\migrations\*.sql | Sort-Object Name | ForEach-Object { Get-Content $_ -Raw | mysql -u root -p warique_orders }
   mysql -u root -p < database\app-user.sql   # edit the password first
   ```
3. Configure and run:
   ```powershell
   cd backend
   copy .env.example .env      # fill real values
   npm install
   npx prisma generate         # never run `prisma migrate`
   npx prisma validate
   npm test
   npm run db:seed             # creates the first OWNER
   # Optional, EMPTY database only: menu, staff, 60 days of sales, supplies, expenses, cash counts
   $env:DEMO_PASSWORD='...'; npm run db:demo   # accounts demo-duenio / demo-mozo / demo-cocina
   npm run start:dev
   ```

## API (prefix `/api`, JWT in `Authorization: Bearer <token>`)

| Method | Path | Roles |
|---|---|---|
| GET | `/health` | public (no business data) |
| POST | `/auth/login` | public |
| GET | `/auth/me` | all |
| PATCH | `/auth/password` | all (own password) |
| GET / POST | `/users` | OWNER |
| PATCH | `/users/:id`, `/users/:id/password` | OWNER |
| GET | `/categories`, `/dishes`, `/dishes/:id`, `/tables` | all |
| POST / PATCH | `/categories`, `/dishes`, `/tables` | OWNER |
| PATCH | `/dishes/:id/availability` | OWNER, KITCHEN |
| POST | `/dishes/availability/reset` | OWNER, KITCHEN |
| GET | `/orders?status=PENDING,IN_PREPARATION&paymentStatus=UNPAID&date=YYYY-MM-DD` | all (without `date`: today plus orders of the previous two days still open or unpaid) |
| GET | `/orders/:id` | all (KITCHEN gets it without payments) |
| POST | `/orders` | WAITER, OWNER (accepts `Idempotency-Key`) |
| PATCH | `/orders/:id/status` | per transition (see `orders/order-status.ts`); a WAITER cancels only their own orders |
| POST | `/orders/:id/payments` | WAITER, OWNER (accepts `Idempotency-Key`) |
| PATCH | `/orders/:id/payments/:paymentId/void` | OWNER (`{ "reason": "..." }`; the order's payment status is recomputed) |
| POST | `/orders/:id/items` | WAITER, OWNER; only while `PENDING`/`IN_PREPARATION` (accepts `Idempotency-Key`) |
| PATCH | `/orders/:id/items/:itemId/cancel` | `PENDING`: WAITER, OWNER; afterwards OWNER only (`{ "reason", "quantity"? }`) |
| GET | `/reports/daily?date=YYYY-MM-DD` | OWNER |
| GET | `/reports/payments?date=YYYY-MM-DD` | OWNER (reconciliation list) |
| GET | `/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD` | OWNER (dashboard, up to 366 days) |
| GET | `/reports/backup-status` | OWNER (reads `BACKUP_STATUS_FILE`) |
| GET | `/supplies`, `/supplies/:id/movements` | OWNER, KITCHEN |
| POST / PATCH | `/supplies`, `/supplies/:id` | OWNER |
| POST | `/supplies/:id/movements` (`COUNT` absolute, `WASTE` / `USE` subtract) | OWNER, KITCHEN (accepts `Idempotency-Key`) |
| GET | `/expenses?date=YYYY-MM-DD`, `/expenses/:id` | OWNER |
| POST | `/expenses` (optional `items`: supply purchase) | OWNER (accepts `Idempotency-Key`) |
| PATCH | `/expenses/:id/void` (with `reason`) | OWNER |
| POST | `/reports/export-link` (`kind`: `ventas` / `pagos` / `gastos` / `arqueos`, `from`, `to`) | OWNER: signed CSV link, valid 2 minutes |
| GET | `/reports/export/:token` | public, the signed link is the credential (owner must still be active) |
| GET | `/cash?date=YYYY-MM-DD` | OWNER |
| POST | `/cash/open` (`openingAmount`), `/cash/close` (`countedAmount`, `notes`) | OWNER |
| POST | `/cash/reopen` | OWNER (clears the closing snapshot so late cash movements can be registered) |

Money values are returned as strings (`"18.50"`) to avoid floating-point rounding; stock
quantities likewise (`"2.500"`, three decimals), computed in integer thousandths.

**Accountant export (CSV).** UTF-8 with BOM, `,` separator, `.` decimals, plain numbers (no
"S/"), one file per kind. Text that a spreadsheet would run as a formula (`=`, `+`, `-`, `@`) is
prefixed with `'` (CSV injection). The download link is signed with a key derived from
`JWT_SECRET` but different from the session key, so a link never works as a session token.

**Supplies, expenses and cash count.**

| Rule | Why |
|---|---|
| Stock only changes through a movement row (`PURCHASE`, `COUNT`, `WASTE`, `USE`, `VOID`) that stores the resulting stock | The history explains every number on screen |
| Stock never goes below zero; a `COUNT` sets the real amount | The system follows the kitchen, not the other way round |
| Selling a dish does **not** deduct supplies (no recipes) | Counts and waste are registered by hand; recipes can come later |
| A purchase (expense with `items`) is always `INSUMOS`, its amount is the sum of the lines, and its stock goes in within the same transaction (rows locked in id order: no deadlocks) | Expense and stock always agree |
| Expenses are voided with a reason, never deleted; voiding a purchase takes its stock back out (refused if part of it was already used: count first) | Audit trail |
| Order lines added after sending are marked (`added_at`); removed lines keep who/when/why (`cancelled_*`) and count in no total, report or kitchen view; the total never drops below what was paid and the last line cannot be removed | Orders change at the table without losing the audit trail |
| Cash payments, cash expenses and their voids are refused on a day whose cash count is closed (`409`) until the owner reopens it | The counted snapshot cannot drift silently |
| Changing or resetting a password increments `users.token_version`: older tokens and sockets are refused at once; sockets also close when their token expires | A lost phone is locked out immediately |
| The kitchen's realtime feed and `GET /orders/:id` carry no payment details | Least privilege |
| Payments are voided by the owner with a reason, never deleted; a voided payment is listed (crossed out) but counts in no balance, report, cash count or daily CSV | A wrong method or amount is fixed without losing the audit trail |
| Expected cash = change fund + cash payments of the day − expenses paid `CASH` that day; closing snapshots expected, counted and the difference (negative = missing); closing again is a recount | The drawer is reconciled every day |
| "Ventas − gastos" is a cash view, not accounting profit | A purchase counts fully on the day it is paid |

**Retries never duplicate orders or payments.** The app sends an `Idempotency-Key` (UUID) with every
new order, added dishes, payment, expense and stock movement, and reuses it when the waiter retries
after a network error; the server runs the request once per user + URL + key and replays the first
result to retries, including retries that arrive while the first request is still running. Successful
responses are also kept 15 minutes in `idempotency_keys` (SHA-256 of the key), so a retry that spans
a restart of the PC is recognised too; older responses are blanked (the app account has no DELETE).
A failed request is not remembered, so it can be retried with the same key.

**Other rules.** Dish prices must be greater than 0 (an order with total 0 could never be paid).
Clients may send `"tableId": null` for takeaway orders.

## Realtime (Socket.IO)

Connect with `io('http://<server-ip>:3000', { auth: { token } })`.
Events: `order.created`, `order.updated`, `dish.updated`, `dishes.reset`, `supply.updated`.

Each socket joins its user room and its role room. Order events reach OWNER and WAITER with the
payments and KITCHEN without them. A socket is refused (or closed) when the user is deactivated, its
role changes, its password changes (`token_version`) or its token expires; the app then reconnects
or goes back to the login screen.

## App (Flutter)

Requirements: Flutter 3.44+ (tested with 3.47.6 / Dart 3.13). Screens in this iteration:

| Role | Screens |
|---|---|
| WAITER | Today's orders (ready / to collect / in kitchen; the phone of the waiter who took an order rings and vibrates when it is ready), new order (table or takeaway, sold-out dishes blocked live; asks before discarding a cart; the cart is kept on the device if the session ends mid-order), order detail: **add dishes** while the kitchen has the order (otherwise "another order for this table"), **remove a dish** while it is pending, deliver, cancel own orders, payment (cash with change, Yape/Plin with operation number) |
| KITCHEN | Live board (pending / in preparation, FIFO, late orders in red; a chime for every new order or added dish (marked **AGREGADO**), repeated every 30 s until someone starts it; a buzz and a "NO preparar" warning when an order or a dish is cancelled; the screen stays on while the board is open; the list reloads when the day changes), sold-out switches, **Insumos** (stock with "por comprar" list, counts, waste, use, history; low-stock count badge on the tab) |
| OWNER | Waiter and kitchen screens (and removing dishes the kitchen already started), plus **Cierre** (daily closing: sales, collections, expenses and sales − expenses, **cash count** with the difference shown as "Cuadra" / "Faltan" / "Sobran", recount and reopen, collections per method, top dishes, every payment with its Yape/Plin operation number (tap to open the order and void a wrong payment), backup health including whether Google Drive was running to upload it; **Estadísticas**: sales per day, weekday averages, top dishes by quantity or revenue, orders per hour, payment split and expenses by category for 7/30/90 days or this month, each chart with a table view) **Exportar para el contador** (CSV of daily sales, payments, expenses and cash counts for last month, this month or any range) and **Gestión** (**expenses** with optional supply lines, voiding with a reason; **supplies** with minimum stock alerts; menu with categories, prices and sold-out switches; tables; staff accounts and password resets; QR codes to connect staff phones) |
| All | Change own password from the account menu (ends the account's other sessions) |

```powershell
cd app
flutter pub get
dart format lib test                 # code style (110 columns, analysis_options.yaml)
flutter analyze
flutter test                         # unit + widget tests, includes a parity check against
                                     # backend/src/orders/order-status.ts
flutter run -d chrome --web-port 8080
flutter build web --release --no-web-resources-cdn   # no Google CDN needed at runtime
flutter build apk --release --dart-define=API_URL=http://192.168.1.50:3000
```

- **Server address**: entered on the login screen and saved on the device. The web build
  defaults to `http://<same host>:3000`; `--dart-define=API_URL=...` sets the default at build time.
- **Web build in production**: the backend serves it from `backend/public` (or `WEB_DIR`) on the
  same port as the API, so no CORS setup is needed. `CORS_ORIGINS` is only for `flutter run`.
- **Android**: the API is plain HTTP on the local network, so the manifest enables
  `usesCleartextTraffic`. Keep staff devices on a Wi-Fi network separate from the customers' one.
- **Deactivating a user or resetting their password** closes their Socket.IO connections
  immediately; their HTTP requests are refused on the next call (the guard re-reads the user and
  their `token_version` on every request).
- **Alerts**: bundled tones in `app/assets/sounds/` (see its `LEEME.md`). On the web they play through
  one Web Audio context unlocked by the first tap ("Activar" on the kitchen board); Android uses
  `audioplayers`. The kitchen board keeps the screen on (`wakelock_plus`).
- **Realtime**: the green/red dot in the app bar shows the Socket.IO link. After every reconnection
  the app reloads the orders and the menu, so events missed while offline are recovered. It also
  reloads when the app comes back to the foreground and when the day changes.

### Android APK

Without a release key the APK is signed with the machine's debug key, and Android refuses to update
an app signed with a different key. Create the project's key **once**, on the machine that builds the
APK (it never leaves it):

```powershell
powershell -ExecutionPolicy Bypass -File deploy\windows\new-android-key.ps1
```

It finds `keytool` (JAVA_HOME, PATH or Android Studio's bundled JDK), creates
`%USERPROFILE%\WariqueLlaves\warique.jks` (PKCS12, RSA 2048) with a random password passed through an
environment variable, writes `app/android/key.properties` (refuses if git would not ignore it) and a
`LEEME-respaldo.txt` with the password and the SHA-256 fingerprint. It never overwrites an existing key.
Back up that folder in two safe places: losing the key means reinstalling the app on every phone. The
CI's APK job creates its throwaway key with the same script and checks the APK carries that fingerprint.

`app/android/key.properties` (git-ignored) has this format, if you set it up by hand on another machine:

```properties
storeFile=C:/keys/warique.jks
storePassword=...
keyAlias=warique
keyPassword=...
```

## Deployment (Windows)

One Windows PC in the restaurant runs MySQL and the `Warique` service; phones and tablets use the
app over the local Wi-Fi at `http://<pc-ip>:3000`. Full runbook (Spanish):
[deploy/windows/GUIA-INSTALACION.md](deploy/windows/GUIA-INSTALACION.md).

```powershell
# Development machine: tests, builds and packages everything into release\warique-<version>.zip
# (-WithInstaller, on Windows with Inno Setup 6: also release\Warique-Setup-<version>.exe)
powershell -ExecutionPolicy Bypass -File deploy\windows\build-release.ps1 -WithApk -WithInstaller

# Restaurant PC: double-click Warique-Setup-<version>.exe (installs, or updates an existing install)
# or, as administrator inside the extracted package:
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -GoogleDrive
```

| Concern | Decision |
|---|---|
| Service manager | [WinSW 2.12](https://github.com/winsw/winsw) (MIT), SHA256 pinned in `build-release.ps1`; restart on failure, size-rotated logs, depends on the MySQL service. MySQL also gets restart-on-failure (`sc.exe failure`, install and update) |
| Service account | `NT AUTHORITY\LocalService`: reads the app and `.env`, writes only `logs\` |
| Secrets | `config\.env` and MySQL option files, ACL Administrators + SYSTEM (+ service read on `.env`); MySQL passwords are random and never typed on a command line |
| Network | One port (app + API + Socket.IO), firewall rule for Private networks only; MySQL bound to `127.0.0.1` |
| Offline package | Node.js 22 for Windows (pinned SHA256, `app\runtime\node.exe`), production `node_modules` and the Prisma Windows engine are bundled: no internet, Node.js or build tools needed on the PC. The runtime lives inside `app`, so an update and its rollback swap it together with the code |
| Installer | `Warique-Setup-<version>.exe` (Inno Setup 6, Spanish wizard): MySQL root password, owner account, Google Drive and network options; extracts the package to `C:\ProgramData\WariqueInstalador` and runs the same `install.ps1` / `update.ps1` through `setup-run.ps1` (secrets passed as environment variables, never on a command line). Unsigned for now (SmartScreen shows "Unknown publisher"); verify it with the `.sha256` file. CI installs through it silently |
| Backups | Daily at 19:30, after the cash count (`mysqldump --single-transaction`, task as SYSTEM, runs late if the PC was off), integrity check, zip + SHA256, 30-day retention, copy to the owner's Google Drive (desktop client in *Mirror files* mode: *Stream files* mounts a per-user drive SYSTEM cannot see). The status records whether Google Drive was running to upload it, and the owner's card turns red when it was not; the installer tests the copy through the real scheduled task |
| Restore | `restore.ps1`: safety backup first, drops and reloads the database (nothing of the current state survives), then applies the migrations the backup lacks |
| Updates | `update.ps1`: backup, pending schema migrations, swap `app` / `app.previous`, health check, automatic rollback; if the current version cannot be moved aside (a locked file) the service is started again and nothing changes |
| Schema changes | `database/migrations/NNN_*.sql`, idempotent and additive only (the previous version keeps working if an update rolls back); recorded in `schema_migrations`. A copy is kept in `C:\Warique\database\migrations` so `status.ps1` flags any change that was not applied (update cut short). Pending ones are detected with the read-only backup account, so the MySQL root password is asked only when there is something to apply (or taken from `WARIQUE_MYSQL_ADMIN_PASSWORD`) |
| Windows | No sleep/hibernate on AC power, Windows Update active hours 08:00–22:00 (opening 11:00–18:00, cash count by 19:00, backup 19:30) |

## Continuous integration

`.github/workflows/verify.yml` runs on every push:

- **Windows** (PowerShell 5.1, MySQL 8.4 as a service, Peru time zone): builds the release with all
  backend and app tests, installs it with `Warique-Setup.exe` in silent mode and runs
  `verify-windows-install.ps1`: service and ACLs, the business flow (orders, edits, payments,
  voids, expenses, cash count), session invalidation, backups and Google Drive status, restore,
  update with a new migration, rollback of a broken release. The release package and installer are
  uploaded as the `warique-release-windows` artifact.
- **Android**: signed release APK with a throwaway key made by `new-android-key.ps1`.

## Conventions

- Branches: `main` is what gets installed; work happens in feature branches merged through pull
  requests once CI is green.
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
- Versions: `backend/package.json` (server, shown in `/api/health` and the installer name) and
  `app/pubspec.yaml` (app); both change in the same pull request.
