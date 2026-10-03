# Warique Orders

Order, kitchen and payment management system for a small restaurant (warique).
Runs on a local Windows server inside the restaurant's network.

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
│       ├── orders/       # Orders, status machine, payments
│       ├── reports/      # Daily cash closing and the sales/expenses dashboard
│       ├── supplies/     # Supplies with stock: counts, waste, use (every change is a movement)
│       ├── expenses/     # Expenses; a supply purchase adds stock in the same transaction
│       ├── cash/         # Daily cash count (arqueo): change fund, expected vs counted
│       ├── realtime/     # Socket.IO gateway
│       ├── health/       # GET /api/health (database + MySQL time zone check)
│       ├── cli/          # create-owner: first OWNER account from a production build
│       └── common/       # Filters, DTO helpers, money/quantity and date utils
└── app/                  # Flutter 3.44+ (Android + web), Riverpod 3, Socket.IO client
    └── lib/
        ├── core/         # HTTP client, error translation, Money (cents), Quantity (thousandths)
        ├── models/       # Order, Dish, User + client copy of the status machine
        ├── data/         # Repositories, Socket.IO client, saved server/token
        ├── state/        # Riverpod providers: session, today's orders, menu
        └── ui/           # login, waiter/, kitchen/, owner/, inventory/, widgets/
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
| GET | `/orders?status=PENDING,IN_PREPARATION&paymentStatus=UNPAID&date=YYYY-MM-DD` | all |
| GET | `/orders/:id` | all |
| POST | `/orders` | WAITER, OWNER (accepts `Idempotency-Key`) |
| PATCH | `/orders/:id/status` | per transition (see `orders/order-status.ts`) |
| POST | `/orders/:id/payments` | WAITER, OWNER (accepts `Idempotency-Key`) |
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
| GET | `/cash?date=YYYY-MM-DD` | OWNER |
| POST | `/cash/open` (`openingAmount`), `/cash/close` (`countedAmount`, `notes`) | OWNER |

Money values are returned as strings (`"18.50"`) to avoid floating-point rounding; stock
quantities likewise (`"2.500"`, three decimals), computed in integer thousandths.

**Supplies, expenses and cash count.**

| Rule | Why |
|---|---|
| Stock only changes through a movement row (`PURCHASE`, `COUNT`, `WASTE`, `USE`, `VOID`) that stores the resulting stock | The history explains every number on screen |
| Stock never goes below zero; a `COUNT` sets the real amount | The system follows the kitchen, not the other way round |
| Selling a dish does **not** deduct supplies (no recipes) | Counts and waste are registered by hand; recipes can come later |
| A purchase (expense with `items`) is always `INSUMOS`, its amount is the sum of the lines, and its stock goes in within the same transaction (rows locked in id order: no deadlocks) | Expense and stock always agree |
| Expenses are voided with a reason, never deleted; voiding a purchase takes its stock back out (refused if part of it was already used: count first) | Audit trail |
| Expected cash = change fund + cash payments of the day − expenses paid `CASH` that day; closing snapshots expected, counted and the difference (negative = missing); closing again is a recount | The drawer is reconciled every day |
| "Ventas − gastos" is a cash view, not accounting profit | A purchase counts fully on the day it is paid |

**Retries never duplicate orders or payments.** The app sends an `Idempotency-Key` (UUID) with every
new order and payment and reuses it when the waiter retries after a network error; the server runs
the request once per user + URL + key and replays the first result to retries, including retries
that arrive while the first request is still running. Keys live in memory for 15 minutes (single
API process); a failed request is not remembered, so it can be retried with the same key.

## Realtime (Socket.IO)

Connect with `io('http://<server-ip>:3000', { auth: { token } })`.
Events: `order.created`, `order.updated`, `dish.updated`, `dishes.reset`, `supply.updated`.

## App (Flutter)

Requirements: Flutter 3.44+ (tested with 3.47.6 / Dart 3.13). Screens in this iteration:

| Role | Screens |
|---|---|
| WAITER | Today's orders (ready / to collect / in kitchen), new order (or "another order for this table" from an order's detail) (table or takeaway, sold-out dishes blocked live), order detail, deliver, cancel, payment (cash with change, Yape/Plin with operation number) |
| KITCHEN | Live board (pending / in preparation, FIFO, late orders in red, alert on cancellations), sold-out switches, **Insumos** (stock with "por comprar" list, counts, waste, use, history; low-stock count badge on the tab) |
| OWNER | Waiter and kitchen screens, plus **Cierre** (daily closing: sales, collections, expenses and sales − expenses, **cash count** with the difference shown as "Cuadra" / "Faltan" / "Sobran", collections per method, top dishes, every payment with its Yape/Plin operation number, backup health; **Estadísticas**: sales per day, weekday averages, top dishes by quantity or revenue, orders per hour, payment split and expenses by category for 7/30/90 days or this month, each chart with a table view) and **Gestión** (**expenses** with optional supply lines, voiding with a reason; **supplies** with minimum stock alerts; menu with categories, prices and sold-out switches; tables; staff accounts and password resets; QR codes to connect staff phones) |
| All | Change own password from the account menu |

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
- **Deactivating a user** closes their Socket.IO connections immediately; their HTTP requests are
  refused on the next call (the guard re-reads the user on every request).
- **Realtime**: the green/red dot in the app bar shows the Socket.IO link. After every reconnection
  the app reloads the orders and the menu, so events missed while offline are recovered.

### Android APK

Without a release key the APK is signed with the machine's debug key, and Android refuses to update
an app signed with a different key. Create one key per project and keep it (and its passwords)
outside the repository:

```powershell
keytool -genkey -v -keystore C:\keys\warique.jks -keyalg RSA -keysize 2048 -validity 10000 -alias warique
```

Then `app/android/key.properties` (git-ignored):

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
powershell -ExecutionPolicy Bypass -File deploy\windows\build-release.ps1 -WithApk

# Restaurant PC (as administrator, inside the extracted package)
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -GoogleDrive
```

| Concern | Decision |
|---|---|
| Service manager | [WinSW 2.12](https://github.com/winsw/winsw) (MIT), SHA256 pinned in `build-release.ps1`; restart on failure, size-rotated logs, depends on the MySQL service |
| Service account | `NT AUTHORITY\LocalService`: reads the app and `.env`, writes only `logs\` |
| Secrets | `config\.env` and MySQL option files, ACL Administrators + SYSTEM (+ service read on `.env`); MySQL passwords are random and never typed on a command line |
| Network | One port (app + API + Socket.IO), firewall rule for Private networks only; MySQL bound to `127.0.0.1` |
| Offline package | Production `node_modules` and the Prisma Windows engine are bundled: no internet or build tools needed on the PC |
| Backups | Daily `mysqldump --single-transaction` (task as SYSTEM, runs late if the PC was off), integrity check, zip + SHA256, 30-day retention, copy to the owner's Google Drive (desktop client in *Mirror files* mode: *Stream files* mounts a per-user drive SYSTEM cannot see); the installer tests the copy through the real scheduled task |
| Updates | `update.ps1`: backup, pending schema migrations, swap `app` / `app.previous`, health check, automatic rollback |
| Schema changes | `database/migrations/NNN_*.sql`, idempotent and additive only (the previous version keeps working if an update rolls back); recorded in `schema_migrations`. A copy is kept in `C:\Warique\database\migrations` so `status.ps1` flags any change that was not applied (update cut short). Pending ones are detected with the read-only backup account, so the MySQL root password is asked only when there is something to apply (or taken from `WARIQUE_MYSQL_ADMIN_PASSWORD`) |
| Windows | No sleep/hibernate on AC power, Windows Update active hours set to the opening hours |

## Conventions

- Branches: `main` (production), `develop`, `feature/*`
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
