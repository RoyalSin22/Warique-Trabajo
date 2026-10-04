// Development helper: fills an EMPTY database with realistic demo data (`npm run db:demo`).
// Menu, tables, staff, 60 days of paid orders, supplies with purchases and counts, expenses and
// closed cash counts, plus a few open orders today. Never run it at the restaurant:
// - it refuses to touch a database that already has orders;
// - it needs DEMO_PASSWORD (no default password ends up on a real install);
// - it is not part of the release package (prisma/ and ts-node are excluded).
import {
  MovementType,
  OrderStatus,
  PaidWith,
  PaymentMethod,
  Prisma,
  PrismaClient,
  Role,
} from '@prisma/client';
import { hashPassword } from '../src/auth/password.util';
import { fromCents } from '../src/common/utils/money';
import { fromMilli } from '../src/common/utils/quantity';

const DAYS = 60;
const prisma = new PrismaClient();
const offsetMs = Number(process.env.BUSINESS_UTC_OFFSET_MINUTES ?? -300) * 60_000;

// Deterministic: the same demo every time (mulberry32)
let seed = 20261003;
function random(): number {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const between = (min: number, max: number) => min + Math.floor(random() * (max - min + 1));
function weighted<T>(items: T[], weights: number[]): T {
  let pick = random() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < items.length; i++) if ((pick -= weights[i]) < 0) return items[i];
  return items[items.length - 1];
}

/** UTC instant of a local business time. */
const at = (day: string, hour: number, minute: number) =>
  new Date(Date.parse(`${day}T00:00:00Z`) + (hour * 60 + minute) * 60_000 - offsetMs);
const dateColumn = (day: string) => new Date(`${day}T00:00:00.000Z`);

const MENU: [string, string, number, number][] = [
  // category, dish, price (cents), popularity
  ['Entradas', 'Papa a la huancaína', 1200, 5],
  ['Entradas', 'Causa limeña', 1400, 4],
  ['Entradas', 'Tequeños', 1000, 3],
  ['Fondos', 'Ceviche', 1850, 9],
  ['Fondos', 'Lomo saltado', 2450, 8],
  ['Fondos', 'Ají de gallina', 1500, 6],
  ['Fondos', 'Arroz con pato', 2200, 5],
  ['Fondos', 'Seco de res', 2000, 4],
  ['Bebidas', 'Chicha morada', 300, 9],
  ['Bebidas', 'Inca Kola', 400, 6],
  ['Bebidas', 'Limonada', 500, 5],
];

// name, unit, minimum, typical purchase (milli), price per unit (cents)
const SUPPLIES: [string, 'KG' | 'L' | 'UNIDAD' | 'ATADO', number, number, number][] = [
  ['Pescado', 'KG', 3000, 6000, 2200],
  ['Limón', 'KG', 2000, 4000, 450],
  ['Cebolla roja', 'KG', 3000, 3000, 350],
  ['Pollo', 'KG', 4000, 6000, 1100],
  ['Carne de res', 'KG', 3000, 4000, 2800],
  ['Ají amarillo', 'KG', 1000, 1000, 900],
  ['Arroz', 'KG', 10000, 10000, 420],
  ['Aceite', 'L', 3000, 5000, 950],
  ['Culantro', 'ATADO', 3000, 6000, 100],
  ['Huevos', 'UNIDAD', 30000, 60000, 50],
];

async function main() {
  const password = process.env.DEMO_PASSWORD ?? '';
  if (password.length < 10) throw new Error('Set DEMO_PASSWORD (10+ characters) for the demo accounts');
  if ((await prisma.order.count()) > 0) {
    throw new Error('The database already has orders: the demo only fills an empty database');
  }

  const hash = await hashPassword(password);
  const user = (username: string, fullName: string, role: Role) =>
    prisma.user.upsert({
      where: { username },
      update: {},
      create: { username, fullName, role, passwordHash: hash },
    });
  const owner =
    (await prisma.user.findFirst({ where: { role: Role.OWNER, isActive: true } })) ??
    (await user('demo-duenio', 'Dueño Demo', Role.OWNER));
  const waiter = await user('demo-mozo', 'Rosa Mozo', Role.WAITER);
  await user('demo-cocina', 'Carlos Cocina', Role.KITCHEN);

  const categories = new Map<string, number>();
  for (const [i, name] of ['Entradas', 'Fondos', 'Bebidas'].entries()) {
    const category = await prisma.category.upsert({
      where: { name },
      update: {},
      create: { name, sortOrder: i + 1 },
    });
    categories.set(name, category.id);
  }
  const dishes: { id: number; name: string; cents: number; popularity: number }[] = [];
  for (const [category, name, cents, popularity] of MENU) {
    const categoryId = categories.get(category)!;
    const dish = await prisma.dish.upsert({
      where: { categoryId_name: { categoryId, name } },
      update: {},
      create: { categoryId, name, price: fromCents(cents) },
    });
    dishes.push({ id: dish.id, name, cents, popularity });
  }
  const tables: number[] = [];
  for (let i = 1; i <= 6; i++) {
    tables.push(
      (
        await prisma.diningTable.upsert({
          where: { label: `Mesa ${i}` },
          update: {},
          create: { label: `Mesa ${i}` },
        })
      ).id,
    );
  }
  // step: kilos and litres in 0.1 units, pieces and bunches whole
  const supplies: { id: number; name: string; buy: number; price: number; stock: number; step: number }[] = [];
  for (const [name, unit, min, buy, price] of SUPPLIES) {
    const supply = await prisma.supply.upsert({
      where: { name },
      update: {},
      create: { name, unit, minStock: fromMilli(min) },
    });
    supplies.push({ id: supply.id, name, buy, price, stock: 0, step: unit === 'KG' || unit === 'L' ? 100 : 1000 });
  }

  const today = new Date(Date.now() + offsetMs).toISOString().slice(0, 10);
  const day0 = Date.parse(`${today}T00:00:00Z`);
  let orders = 0;

  for (let back = DAYS; back >= 0; back--) {
    const day = new Date(day0 - back * 86_400_000).toISOString().slice(0, 10);
    const weekday = new Date(`${day}T00:00:00Z`).getUTCDay(); // 0 = Sunday
    if (weekday === 1) continue; // closed on Mondays
    const isToday = back === 0;
    const movements: Prisma.SupplyMovementCreateManyInput[] = [];

    await prisma.$transaction(
      async (tx) => {
        // Morning purchase at the market, paid from the drawer
        const bought = supplies.filter((s, i) => i < 3 || random() < 0.35);
        const lines = bought.map((s) => {
          const milli = Math.max(s.step, Math.round((s.buy * (0.7 + random() * 0.6)) / s.step) * s.step);
          return { supply: s, milli, cents: Math.round((milli * s.price * (0.9 + random() * 0.2)) / 1000) };
        });
        const purchaseCents = lines.reduce((sum, l) => sum + l.cents, 0);
      // Small purchases come out of the drawer; big ones the owner pays by Yape (keeps the drawer positive)
      const purchaseWith = purchaseCents <= 15000 ? PaidWith.CASH : PaidWith.OTHER;
        const purchase = await tx.expense.create({
          data: {
            businessDate: dateColumn(day),
            category: 'INSUMOS',
            description: 'Mercado mayorista',
            amount: fromCents(purchaseCents),
            paidWith: purchaseWith,
            createdBy: owner.id,
            createdAt: at(day, 8, 30),
            items: {
              create: lines.map((l) => ({
                supplyId: l.supply.id,
                quantity: fromMilli(l.milli),
                cost: fromCents(l.cents),
              })),
            },
          },
        });
        for (const l of lines) {
          l.supply.stock += l.milli;
          movements.push({
            supplyId: l.supply.id,
            type: MovementType.PURCHASE,
            quantity: fromMilli(l.milli),
            stockAfter: fromMilli(l.supply.stock),
            expenseId: purchase.id,
            createdBy: owner.id,
            createdAt: at(day, 8, 30),
          });
        }
        let cashExpenses = purchaseWith === PaidWith.CASH ? purchaseCents : 0;
        const other: [string, string, number, PaidWith][] = [];
        if (weekday === 3) other.push(['GAS', 'Balón de gas 10 kg', 5800, PaidWith.CASH]);
        if (weekday === 6) other.push(['SUELDOS', 'Pago semanal ayudante', 35000, PaidWith.OTHER]);
        if (day.endsWith('-01')) other.push(['ALQUILER', 'Alquiler del local', 120000, PaidWith.OTHER]);
        if (day.endsWith('-05'))
          other.push(['SERVICIOS', 'Luz y agua', between(18000, 24000), PaidWith.OTHER]);
        for (const [category, description, cents, paidWith] of other) {
          await tx.expense.create({
            data: {
              businessDate: dateColumn(day),
              category: category as never,
              description,
              amount: fromCents(cents),
              paidWith,
              createdBy: owner.id,
              createdAt: at(day, 10, 0),
            },
          });
          if (paidWith === PaidWith.CASH) cashExpenses += cents;
        }

        // Service 11:00-18:00, busier on weekends
        const base = { 0: 26, 2: 13, 3: 14, 4: 16, 5: 20, 6: 30 }[weekday as 0 | 2 | 3 | 4 | 5 | 6]!;
        const count = isToday ? 7 : Math.max(4, Math.round(base * (0.8 + random() * 0.4)));
        let cashSales = 0;
        for (let n = 0; n < count; n++) {
          const created = at(
            day,
            weighted([11, 12, 13, 14, 15, 16, 17], [4, 14, 18, 11, 6, 4, 3]),
            between(0, 59),
          );
          const items = Array.from({ length: weighted([1, 2, 3, 4], [3, 5, 3, 1]) }, () => {
            const dish = weighted(
              dishes,
              dishes.map((d) => d.popularity),
            );
            return { dish, quantity: weighted([1, 2, 3], [6, 3, 1]) };
          });
          const totalCents = items.reduce((sum, i) => sum + i.dish.cents * i.quantity, 0);
          const takeaway = random() < 0.25;
          // Today: the last orders are still moving through the kitchen
          const status =
            !isToday || n < count - 4
              ? OrderStatus.DELIVERED
              : [OrderStatus.PENDING, OrderStatus.PENDING, OrderStatus.IN_PREPARATION, OrderStatus.READY][
                  n - (count - 4)
                ];
          const paid = status === OrderStatus.DELIVERED;
          const method = weighted([PaymentMethod.CASH, PaymentMethod.YAPE, PaymentMethod.PLIN], [45, 42, 13]);
          const paidAt = new Date(created.getTime() + 40 * 60_000);
          if (paid && method === PaymentMethod.CASH) cashSales += totalCents;
          await tx.order.create({
            data: {
              orderType: takeaway ? 'TAKEAWAY' : 'DINE_IN',
              tableId: takeaway ? null : tables[between(0, tables.length - 1)],
              customerName: takeaway
                ? weighted(['Juan', 'Sra. Carmen', 'Jorge', 'Lucía', null], [1, 1, 1, 1, 3])
                : null,
              waiterId: waiter.id,
              status,
              paymentStatus: paid ? 'PAID' : 'UNPAID',
              total: fromCents(totalCents),
              createdAt: created,
              updatedAt: paid ? paidAt : created,
              paidAt: paid ? paidAt : null,
              items: {
                create: items.map((i) => ({
                  dishId: i.dish.id,
                  dishName: i.dish.name,
                  unitPrice: fromCents(i.dish.cents),
                  quantity: i.quantity,
                })),
              },
              payments: paid
                ? {
                    create: {
                      method,
                      amount: fromCents(totalCents),
                      amountReceived:
                        method === PaymentMethod.CASH
                          ? fromCents(
                              [totalCents, 1000, 2000, 5000, 10000, 20000].find((b) => b >= totalCents)!,
                            )
                          : null,
                      operationNumber:
                        method === PaymentMethod.CASH ? null : String(between(10_000_000, 99_999_999)),
                      registeredBy: waiter.id,
                      createdAt: paidAt,
                    },
                  }
                : undefined,
            },
          });
          orders++;
        }

        // Closing: the kitchen counts what is left (no recipes: counts keep the stock real)
        if (!isToday) {
          for (const s of supplies) {
            const left = Math.round((s.stock * (0.15 + random() * 0.35)) / s.step) * s.step;
            movements.push({
              supplyId: s.id,
              type: MovementType.COUNT,
              quantity: fromMilli(left - s.stock),
              stockAfter: fromMilli(left),
              createdBy: owner.id,
              createdAt: at(day, 18, 15),
            });
            s.stock = left;
          }
        }
        await tx.supplyMovement.createMany({ data: movements });

        // Cash count: mostly exact, sometimes a few soles off
        const expected = 20000 + cashSales - cashExpenses;
        const diff = weighted([0, -250, -500, 100], [14, 3, 1, 2]);
        await tx.cashSession.create({
          data: {
            businessDate: dateColumn(day),
            openingAmount: fromCents(20000),
            openedBy: owner.id,
            openedAt: at(day, 10, 45),
            ...(isToday
              ? {}
              : {
                  expectedAmount: fromCents(expected),
                  countedAmount: fromCents(Math.max(0, expected + diff)),
                  difference: fromCents(Math.max(0, expected + diff) - expected),
                  notes: diff < 0 ? 'Faltó vuelto' : null,
                  closedBy: owner.id,
                  closedAt: at(day, 18, 30),
                }),
          },
        });
      },
      { timeout: 60_000 },
    );
  }

  for (const s of supplies)
    await prisma.supply.update({ where: { id: s.id }, data: { stock: fromMilli(s.stock) } });
  console.log(`Demo data: ${orders} orders over ${DAYS} days, ${supplies.length} supplies.`);
  console.log(`Accounts (password = DEMO_PASSWORD): ${owner.username}, demo-mozo, demo-cocina`);
}

main()
  .catch((error: Error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
