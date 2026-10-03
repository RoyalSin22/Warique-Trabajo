import { PaymentMethod } from '@prisma/client';
import { fromCents, toCents } from '../common/utils/money';

/** Inputs already aggregated or fetched by the service, kept free of Prisma for testing. */
export interface SummaryInput {
  /** Business days, inclusive, as YYYY-MM-DD */
  days: string[];
  utcOffsetMinutes: number;
  /** Non-cancelled orders created in the range */
  orders: { createdAt: Date; total: { toString(): string } }[];
  dishes: { dishName: string; quantity: number; revenueCents: number }[];
  payments: { method: PaymentMethod; count: number; amountCents: number }[];
}

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7]; // ISO: Monday = 1

/**
 * Builds the owner's dashboard: daily series (zero-filled), weekday averages over the days that
 * had sales (a closed day must not drag the average down), hourly load, top dishes and the
 * payment-method split. All money is computed in integer cents and returned as "0.00" strings.
 */
export function buildSummary(input: SummaryInput) {
  const offsetMs = input.utcOffsetMinutes * 60_000;
  const byDay = new Map(input.days.map((day) => [day, { salesCents: 0, orders: 0 }]));
  const byHour = new Map<number, { salesCents: number; orders: number }>();

  for (const order of input.orders) {
    const local = new Date(order.createdAt.getTime() + offsetMs);
    const day = local.toISOString().slice(0, 10);
    const cents = toCents(order.total);
    const dayRow = byDay.get(day);
    if (dayRow) {
      dayRow.salesCents += cents;
      dayRow.orders += 1;
    }
    const hour = local.getUTCHours();
    const hourRow = byHour.get(hour) ?? { salesCents: 0, orders: 0 };
    hourRow.salesCents += cents;
    hourRow.orders += 1;
    byHour.set(hour, hourRow);
  }

  const days = [...byDay.entries()].map(([date, row]) => ({
    date,
    weekday: isoWeekday(date),
    sales: fromCents(row.salesCents),
    orders: row.orders,
    salesCents: row.salesCents,
  }));

  const salesCents = days.reduce((sum, day) => sum + day.salesCents, 0);
  const orders = days.reduce((sum, day) => sum + day.orders, 0);
  const best = days.reduce<(typeof days)[number] | null>(
    (top, day) => (day.salesCents > 0 && (!top || day.salesCents > top.salesCents) ? day : top),
    null,
  );

  const byWeekday = WEEKDAYS.map((weekday) => {
    const open = days.filter((day) => day.weekday === weekday && day.orders > 0);
    const total = open.reduce((sum, day) => sum + day.salesCents, 0);
    return {
      weekday,
      openDays: open.length,
      sales: fromCents(total),
      averageSales: fromCents(open.length ? Math.round(total / open.length) : 0),
    };
  });

  const collectedCents = input.payments.reduce((sum, row) => sum + row.amountCents, 0);

  return {
    from: input.days[0],
    to: input.days[input.days.length - 1],
    totals: {
      sales: fromCents(salesCents),
      orders,
      averageTicket: fromCents(orders ? Math.round(salesCents / orders) : 0),
      collected: fromCents(collectedCents),
      daysWithSales: days.filter((day) => day.orders > 0).length,
      bestDay: best ? { date: best.date, sales: best.sales } : null,
    },
    days: days.map(({ salesCents: _omit, ...day }) => day),
    byWeekday,
    byHour: [...byHour.entries()]
      .sort(([a], [b]) => a - b)
      .map(([hour, row]) => ({ hour, orders: row.orders, sales: fromCents(row.salesCents) })),
    topDishes: input.dishes.map((dish) => ({
      dishName: dish.dishName,
      quantity: dish.quantity,
      revenue: fromCents(dish.revenueCents),
    })),
    byMethod: input.payments.map((row) => ({
      method: row.method,
      count: row.count,
      amount: fromCents(row.amountCents),
    })),
  };
}

/** Every YYYY-MM-DD from [from] to [to], inclusive. */
export function dayRange(from: string, to: string): string[] {
  const days: string[] = [];
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= Date.parse(`${to}T00:00:00Z`); t += 86_400_000) {
    days.push(new Date(t).toISOString().slice(0, 10));
  }
  return days;
}

function isoWeekday(date: string): number {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay(); // 0 = Sunday
  return day === 0 ? 7 : day;
}
