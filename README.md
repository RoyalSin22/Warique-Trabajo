# Warique Orders

Order, kitchen and payment management system for a small restaurant (warique).
Runs on a local Windows server inside the restaurant's network.

## Structure

```
warique-orders/
├── database/
│   ├── schema.sql        # Source of truth (MySQL 8.4 LTS; 8.0.16+ works)
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
│       ├── reports/      # Daily cash closing
│       ├── realtime/     # Socket.IO gateway
│       ├── health/       # GET /api/health (database + MySQL time zone check)
│       ├── cli/          # create-owner: first OWNER account from a production build
│       └── common/       # Filters, DTO helpers, money and date utils
└── app/                  # Flutter 3.44+ (Android + web), Riverpod 3, Socket.IO client
    └── lib/
        ├── core/         # HTTP client, error translation, Money (integer cents)
        ├── models/       # Order, Dish, User + client copy of the status machine
        ├── data/         # Repositories, Socket.IO client, saved server/token
        ├── state/        # Riverpod providers: session, today's orders, menu
        └── ui/           # login, waiter/, kitchen/, widgets/
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
| GET | `/reports/backup-status` | OWNER (reads `BACKUP_STATUS_FILE`) |

Money values are returned as strings (`"18.50"`) to avoid floating-point rounding.

**Retries never duplicate orders or payments.** The app sends an `Idempotency-Key` (UUID) with every
new order and payment and reuses it when the waiter retries after a network error; the server runs
the request once per user + URL + key and replays the first result to retries, including retries
that arrive while the first request is still running. Keys live in memory for 15 minutes (single
API process); a failed request is not remembered, so it can be retried with the same key.

## Realtime (Socket.IO)

Connect with `io('http://<server-ip>:3000', { auth: { token } })`.
Events: `order.created`, `order.updated`, `dish.updated`, `dishes.reset`.

## App (Flutter)

Requirements: Flutter 3.44+ (tested with 3.47.6 / Dart 3.13). Screens in this iteration:

| Role | Screens |
|---|---|
| WAITER | Today's orders (ready / to collect / in kitchen), new order (or "another order for this table" from an order's detail) (table or takeaway, sold-out dishes blocked live), order detail, deliver, cancel, payment (cash with change, Yape/Plin with operation number) |
| KITCHEN | Live board (pending / in preparation, FIFO, late orders in red, alert on cancellations), sold-out switches |
| OWNER | Waiter and kitchen screens, plus **Cierre** (daily sales, collections per method, top dishes, every payment with its Yape/Plin operation number, backup health) and **Gestión** (menu with categories, prices and sold-out switches; tables; staff accounts and password resets; QR codes to connect staff phones) |
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
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -BackupCopyDir 'D:\Respaldos'
```

| Concern | Decision |
|---|---|
| Service manager | [WinSW 2.12](https://github.com/winsw/winsw) (MIT), SHA256 pinned in `build-release.ps1`; restart on failure, size-rotated logs, depends on the MySQL service |
| Service account | `NT AUTHORITY\LocalService`: reads the app and `.env`, writes only `logs\` |
| Secrets | `config\.env` and MySQL option files, ACL Administrators + SYSTEM (+ service read on `.env`); MySQL passwords are random and never typed on a command line |
| Network | One port (app + API + Socket.IO), firewall rule for Private networks only; MySQL bound to `127.0.0.1` |
| Offline package | Production `node_modules` and the Prisma Windows engine are bundled: no internet or build tools needed on the PC |
| Backups | Daily `mysqldump --single-transaction` (task as SYSTEM, runs late if the PC was off), integrity check, zip + SHA256, 30-day retention, copy to USB/OneDrive |
| Updates | `update.ps1`: backup, swap `app` / `app.previous`, health check, automatic rollback |
| Windows | No sleep/hibernate on AC power, Windows Update active hours set to the opening hours |

## Conventions

- Branches: `main` (production), `develop`, `feature/*`
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
