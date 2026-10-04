// backend/src/reports/export.ts
// Spreadsheets for the accountant, built from rows the service already fetched (no Prisma here).
import { PaidWith, PaymentMethod } from '@prisma/client';
import { fromCents, toCents } from '../common/utils/money';
import { fromMilli, toMilli } from '../common/utils/quantity';
import { csvNumber, toCsv } from './csv';

export const EXPORT_KINDS = ['ventas', 'pagos', 'gastos', 'arqueos'] as const;
export type ExportKind = (typeof EXPORT_KINDS)[number];

type Decimalish = { toString(): string } | string | null;

const money = (value: Decimalish) => csvNumber(fromCents(toCents(value)));
const quantity = (value: Decimalish) => csvNumber(fromMilli(toMilli(value)).replace(/\.?0+$/, ''));

/** Local business day and time of a UTC timestamp. */
export function localParts(date: Date, utcOffsetMinutes: number) {
  const iso = new Date(date.getTime() + utcOffsetMinutes * 60_000).toISOString();
  return { day: iso.slice(0, 10), time: iso.slice(11, 16) };
}

const METHOD_LABEL: Record<PaymentMethod, string> = { CASH: 'Efectivo', YAPE: 'Yape', PLIN: 'Plin' };
const PAID_WITH_LABEL: Record<PaidWith, string> = { CASH: 'Caja', OTHER: 'Otro medio' };
const CATEGORY_LABEL: Record<string, string> = {
  INSUMOS: 'Insumos',
  GAS: 'Gas',
  SERVICIOS: 'Luz, agua, internet',
  SUELDOS: 'Sueldos',
  ALQUILER: 'Alquiler',
  TRANSPORTE: 'Transporte',
  OTROS: 'Otros',
};
const UNIT_LABEL: Record<string, string> = { KG: 'kg', L: 'L', UNIDAD: 'und.', ATADO: 'atado', PAQUETE: 'paq.' };

export interface DailySalesInput {
  days: string[];
  utcOffsetMinutes: number;
  /** Non-cancelled orders created in the range */
  orders: { createdAt: Date; total: Decimalish }[];
  payments: { createdAt: Date; method: PaymentMethod; amount: Decimalish }[];
  /** Non-void expenses by business day */
  expenses: { date: string; amount: Decimalish }[];
}

/** One row per business day, zero-filled: days without sales also tell the accountant something. */
export function dailySalesCsv(input: DailySalesInput): string {
  const empty = () => ({ orders: 0, sales: 0, CASH: 0, YAPE: 0, PLIN: 0, expenses: 0 });
  const byDay = new Map(input.days.map((day) => [day, empty()]));
  for (const order of input.orders) {
    const row = byDay.get(localParts(order.createdAt, input.utcOffsetMinutes).day);
    if (!row) continue;
    row.orders += 1;
    row.sales += toCents(order.total);
  }
  for (const payment of input.payments) {
    const row = byDay.get(localParts(payment.createdAt, input.utcOffsetMinutes).day);
    if (row) row[payment.method] += toCents(payment.amount);
  }
  for (const expense of input.expenses) {
    const row = byDay.get(expense.date);
    if (row) row.expenses += toCents(expense.amount);
  }

  const totals = empty();
  const rows = [...byDay.entries()].map(([day, row]) => {
    for (const key of Object.keys(totals) as (keyof typeof totals)[]) totals[key] += row[key];
    return [day, ...cells(row)];
  });
  function cells(row: ReturnType<typeof empty>) {
    const collected = row.CASH + row.YAPE + row.PLIN;
    return [
      row.orders,
      csvNumber(fromCents(row.sales)),
      csvNumber(fromCents(row.CASH)),
      csvNumber(fromCents(row.YAPE)),
      csvNumber(fromCents(row.PLIN)),
      csvNumber(fromCents(collected)),
      csvNumber(fromCents(row.expenses)),
      csvNumber(fromCents(row.sales - row.expenses)),
    ];
  }
  return toCsv(
    ['Fecha', 'Pedidos', 'Ventas', 'Cobrado efectivo', 'Cobrado Yape', 'Cobrado Plin', 'Total cobrado', 'Gastos', 'Ventas menos gastos'],
    [...rows, ['TOTAL', ...cells(totals)]],
  );
}

export interface PaymentRow {
  createdAt: Date;
  orderId: number;
  method: PaymentMethod;
  amount: Decimalish;
  amountReceived: Decimalish;
  changeGiven: Decimalish;
  operationNumber: string | null;
  registeredBy: string;
  target: string;
}

export function paymentsCsv(rows: PaymentRow[], utcOffsetMinutes: number): string {
  return toCsv(
    ['Fecha', 'Hora', 'Pedido', 'Mesa / cliente', 'Método', 'Monto', 'Recibido', 'Vuelto', 'N.° de operación', 'Registró'],
    rows.map((row) => {
      const { day, time } = localParts(row.createdAt, utcOffsetMinutes);
      return [
        day,
        time,
        row.orderId,
        row.target,
        METHOD_LABEL[row.method],
        money(row.amount),
        row.amountReceived === null ? null : money(row.amountReceived),
        row.changeGiven === null ? null : money(row.changeGiven),
        row.operationNumber,
        row.registeredBy,
      ];
    }),
  );
}

export interface ExpenseRow {
  businessDate: string;
  category: string;
  description: string;
  paidWith: PaidWith;
  amount: Decimalish;
  isVoid: boolean;
  voidReason: string | null;
  createdBy: string;
  items: { supplyName: string; unit: string; quantity: Decimalish; cost: Decimalish }[];
}

/** Voided expenses are listed (with the reason) so the numbers can be audited, but never summed. */
export function expensesCsv(rows: ExpenseRow[]): string {
  return toCsv(
    ['Fecha', 'Categoría', 'Descripción', 'Pagado con', 'Monto', 'Estado', 'Motivo de anulación', 'Detalle de insumos', 'Registró'],
    rows.map((row) => [
      row.businessDate,
      CATEGORY_LABEL[row.category] ?? row.category,
      row.description,
      PAID_WITH_LABEL[row.paidWith],
      money(row.amount),
      row.isVoid ? 'ANULADO' : 'Válido',
      row.voidReason,
      row.items
        .map((item) => `${item.supplyName} ${quantity(item.quantity).value} ${UNIT_LABEL[item.unit] ?? item.unit} S/ ${fromCents(toCents(item.cost))}`)
        .join('; ') || null,
      row.createdBy,
    ]),
  );
}

export interface CashRow {
  businessDate: string;
  openingAmount: Decimalish;
  expectedAmount: Decimalish;
  countedAmount: Decimalish;
  difference: Decimalish;
  notes: string | null;
  openedBy: string;
  closedBy: string | null;
  closedAt: Date | null;
}

export function cashCsv(rows: CashRow[], utcOffsetMinutes: number): string {
  return toCsv(
    ['Fecha', 'Fondo inicial', 'Debe haber', 'Contado', 'Diferencia', 'Resultado', 'Observación', 'Abrió', 'Cerró', 'Hora de cierre'],
    rows.map((row) => {
      const closed = row.closedAt !== null;
      const diff = toCents(row.difference);
      return [
        row.businessDate,
        money(row.openingAmount),
        closed ? money(row.expectedAmount) : null,
        closed ? money(row.countedAmount) : null,
        closed ? money(row.difference) : null,
        !closed ? 'Sin cerrar' : diff === 0 ? 'Cuadra' : diff < 0 ? 'Faltante' : 'Sobrante',
        row.notes,
        row.openedBy,
        row.closedBy,
        row.closedAt ? localParts(row.closedAt, utcOffsetMinutes).time : null,
      ];
    }),
  );
}
