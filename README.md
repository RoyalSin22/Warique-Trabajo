# Warique Orders

Order, kitchen and payment management system for a small restaurant (warique).
Runs on a local Windows server inside the restaurant's network.

## Structure

```
warique-orders/
├── database/
│   ├── schema.sql        # Source of truth (MySQL 8.0.16+)
│   └── app-user.sql      # Least-privilege DB user (no DELETE, no DDL)
├── backend/              # NestJS 11 + Prisma 6 (client only) + Socket.IO
│   └── src/
│       ├── auth/         # JWT login, guards, own password change
│       ├── users/        # Staff accounts (OWNER only)
│       ├── menu/         # Categories and dishes, sold-out toggle
│       ├── tables/       # Dining tables
│       ├── orders/       # Orders, status machine, payments
│       ├── reports/      # Daily cash closing
│       ├── realtime/     # Socket.IO gateway
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

Requirements: Node.js 22 LTS, MySQL 8.0.16+.

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
| POST | `/orders` | WAITER, OWNER |
| PATCH | `/orders/:id/status` | per transition (see `orders/order-status.ts`) |
| POST | `/orders/:id/payments` | WAITER, OWNER |
| GET | `/reports/daily?date=YYYY-MM-DD` | OWNER |

Money values are returned as strings (`"18.50"`) to avoid floating-point rounding.

## Realtime (Socket.IO)

Connect with `io('http://<server-ip>:3000', { auth: { token } })`.
Events: `order.created`, `order.updated`, `dish.updated`, `dishes.reset`.

## App (Flutter)

Requirements: Flutter 3.44+ (tested with 3.47.6 / Dart 3.13). Screens in this iteration:

| Role | Screens |
|---|---|
| WAITER | Today's orders (ready / to collect / in kitchen), new order (table or takeaway, sold-out dishes blocked live), order detail, deliver, cancel, payment (cash with change, Yape/Plin with operation number) |
| KITCHEN | Live board (pending / in preparation, FIFO, late orders in red, alert on cancellations), sold-out switches |
| OWNER | Both of the above. Menu, users and daily report screens are the next iteration |

```powershell
cd app
flutter pub get
flutter analyze
flutter test                         # unit + widget tests, includes a parity check against
                                     # backend/src/orders/order-status.ts
flutter run -d chrome --web-port 8080
flutter build web --release --no-web-resources-cdn   # no Google CDN needed at runtime
flutter build apk --release --dart-define=API_URL=http://192.168.1.50:3000
```

- **Server address**: entered on the login screen and saved on the device. The web build
  defaults to `http://<same host>:3000`; `--dart-define=API_URL=...` sets the default at build time.
- **CORS**: add the origin that serves the web build to `CORS_ORIGINS` in `backend/.env`
  (e.g. `http://192.168.1.50:8080`).
- **Android**: the API is plain HTTP on the local network, so the manifest enables
  `usesCleartextTraffic`. Keep staff devices on a Wi-Fi network separate from the customers' one.
- **Realtime**: the green/red dot in the app bar shows the Socket.IO link. After every reconnection
  the app reloads the orders and the menu, so events missed while offline are recovered.

## Conventions

- Branches: `main` (production), `develop`, `feature/*`
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
