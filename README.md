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
└── app/                  # Flutter (Android + web)  [next iteration]
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

## Conventions

- Branches: `main` (production), `develop`, `feature/*`
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
