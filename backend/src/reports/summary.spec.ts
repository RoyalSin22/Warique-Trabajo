import { PaymentMethod } from '@prisma/client';
import { buildSummary, dayRange } from './summary';

// Peru = UTC-5. 2026-10-03 is a Saturday.
const at = (iso: string, total: string) => ({ createdAt: new Date(iso), total });

describe('dayRange', () => {
  it('lists every day inclusive, across month ends', () => {
    expect(dayRange('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02']);
    expect(dayRange('2026-10-02', '2026-10-01')).toEqual([]);
  });
});

describe('buildSummary', () => {
  const summary = buildSummary({
    days: dayRange('2026-09-28', '2026-10-04'), // Monday..Sunday
    utcOffsetMinutes: -300,
    orders: [
      // 23:30 local on Friday 2 Oct = 04:30Z on the 3rd: must count for Friday, not Saturday
      at('2026-10-03T04:30:00Z', '10.00'),
      at('2026-10-03T17:15:00Z', '40.50'), // Saturday 12:15
      at('2026-10-03T18:40:00Z', '19.50'), // Saturday 13:40
      at('2026-09-28T17:00:00Z', '30.00'), // Monday 12:00
    ],
    dishes: [{ dishName: 'Ceviche', quantity: 5, revenueCents: 9250 }],
    payments: [
      { method: PaymentMethod.CASH, count: 2, amountCents: 5000 },
      { method: PaymentMethod.YAPE, count: 1, amountCents: 4050 },
    ],
  });

  it('assigns orders to the local business day and zero-fills the rest', () => {
    expect(summary.days).toHaveLength(7);
    const byDate = Object.fromEntries(summary.days.map((d) => [d.date, d]));
    expect(byDate['2026-10-02']).toMatchObject({ sales: '10.00', orders: 1, weekday: 5 });
    expect(byDate['2026-10-03']).toMatchObject({ sales: '60.00', orders: 2, weekday: 6 });
    expect(byDate['2026-09-29']).toMatchObject({ sales: '0.00', orders: 0 });
  });

  it('computes exact totals, average ticket and the best day', () => {
    expect(summary.totals).toEqual({
      sales: '100.00',
      orders: 4,
      averageTicket: '25.00',
      collected: '90.50',
      daysWithSales: 3,
      bestDay: { date: '2026-10-03', sales: '60.00' },
    });
  });

  it('averages weekdays over open days only', () => {
    const saturday = summary.byWeekday.find((w) => w.weekday === 6)!;
    const tuesday = summary.byWeekday.find((w) => w.weekday === 2)!;
    expect(saturday).toEqual({ weekday: 6, openDays: 1, sales: '60.00', averageSales: '60.00' });
    expect(tuesday).toEqual({ weekday: 2, openDays: 0, sales: '0.00', averageSales: '0.00' });
  });

  it('groups by local hour, sorted', () => {
    expect(summary.byHour).toEqual([
      { hour: 12, orders: 2, sales: '70.50' },
      { hour: 13, orders: 1, sales: '19.50' },
      { hour: 23, orders: 1, sales: '10.00' },
    ]);
  });

  it('returns no best day when nothing was sold', () => {
    const empty = buildSummary({ days: ['2026-10-01'], utcOffsetMinutes: -300, orders: [], dishes: [], payments: [] });
    expect(empty.totals).toMatchObject({ sales: '0.00', orders: 0, averageTicket: '0.00', bestDay: null });
  });
});
