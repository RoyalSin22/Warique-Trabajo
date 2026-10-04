// backend/src/reports/reports.service.ts
import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus } from '@prisma/client';
import { fromDateColumn, toDateColumn } from '../common/utils/date-column';
import { businessDayRange } from '../common/utils/business-day';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';
import { buildSummary, dayRange } from './summary';

/** Longest range the dashboard accepts (one year). */
const MAX_SUMMARY_DAYS = 366;

@Injectable()
export class ReportsService {
  private readonly utcOffsetMinutes: number;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    this.utcOffsetMinutes = Number(config.get('BUSINESS_UTC_OFFSET_MINUTES') ?? -300);
  }

  /**
   * sales            = totals of the day's non-cancelled orders
   * collectedByMethod = payments registered that day (cash register closing)
   * pendingBalance   = what the day's orders still owe
   */
  async daily(date?: string) {
    const { date: day, start, end } = businessDayRange(date, this.utcOffsetMinutes);
    const createdThatDay = { createdAt: { gte: start, lt: end } };
    const validOrdersThatDay = { ...createdThatDay, status: { not: OrderStatus.CANCELLED } };

    // Aggregate queries in parallel; the database does the summing
    const [ordersByStatus, paymentsByMethod, topDishes, paidOnDayOrders, expenses] = await Promise.all([
      this.prisma.order.groupBy({
        by: ['status'],
        where: createdThatDay,
        _count: { _all: true },
        _sum: { total: true },
      }),
      this.prisma.payment.groupBy({
        by: ['method'],
        where: createdThatDay,
        _count: { _all: true },
        _sum: { amount: true },
      }),
      this.prisma.orderItem.groupBy({
        by: ['dishId', 'dishName'],
        where: { order: validOrdersThatDay },
        _sum: { quantity: true },
        orderBy: { _sum: { quantity: 'desc' } },
        take: 10,
      }),
      this.prisma.payment.aggregate({
        where: { order: validOrdersThatDay },
        _sum: { amount: true },
      }),
      this.prisma.expense.groupBy({
        by: ['category'],
        where: { businessDate: toDateColumn(day), isVoid: false },
        _sum: { amount: true },
      }),
    ]);

    const salesCents = ordersByStatus
      .filter((row) => row.status !== OrderStatus.CANCELLED)
      .reduce((sum, row) => sum + toCents(row._sum.total), 0);
    const collectedCents = paymentsByMethod.reduce((sum, row) => sum + toCents(row._sum.amount), 0);
    const expensesCents = expenses.reduce((sum, row) => sum + toCents(row._sum.amount), 0);

    return {
      date: day,
      orders: ordersByStatus.map((row) => ({
        status: row.status,
        count: row._count._all,
        total: fromCents(toCents(row._sum.total)),
      })),
      sales: fromCents(salesCents),
      collectedByMethod: paymentsByMethod.map((row) => ({
        method: row.method,
        count: row._count._all,
        amount: fromCents(toCents(row._sum.amount)),
      })),
      collectedTotal: fromCents(collectedCents),
      pendingBalance: fromCents(salesCents - toCents(paidOnDayOrders._sum.amount)),
      topDishes: topDishes.map((row) => ({
        dishId: row.dishId,
        dishName: row.dishName,
        quantity: row._sum.quantity ?? 0,
      })),
      expensesTotal: fromCents(expensesCents),
      salesMinusExpenses: fromCents(salesCents - expensesCents),
      expensesByCategory: expenses
        .map((row) => ({ category: row.category, amount: fromCents(toCents(row._sum.amount)) }))
        .sort((a, b) => toCents(b.amount) - toCents(a.amount)),
    };
  }

  /**
   * Every payment registered that day, oldest first: the owner reconciles Yape/Plin operation
   * numbers against the bank app and counts the cash at closing time.
   */
  async payments(date?: string) {
    const { date: day, start, end } = businessDayRange(date, this.utcOffsetMinutes);
    const rows = await this.prisma.payment.findMany({
      where: { createdAt: { gte: start, lt: end } },
      select: {
        id: true,
        orderId: true,
        method: true,
        amount: true,
        amountReceived: true,
        changeGiven: true,
        operationNumber: true,
        createdAt: true,
        registeredUser: { select: { fullName: true } },
        order: { select: { orderType: true, customerName: true, table: { select: { label: true } } } },
      },
      orderBy: { createdAt: 'asc' },
    });
    return {
      date: day,
      payments: rows.map(({ registeredUser, order, ...payment }) => ({
        ...payment,
        registeredBy: registeredUser.fullName,
        target: order.table?.label ?? order.customerName ?? null,
        orderType: order.orderType,
      })),
    };
  }

  /** Owner dashboard for a range of business days (charts in the app's "Cierre" screen). */
  async summary(from: string, to: string) {
    const start = businessDayRange(from, this.utcOffsetMinutes).start;
    const end = businessDayRange(to, this.utcOffsetMinutes).end;
    const days = dayRange(from, to);
    if (days.length === 0) throw new BadRequestException('from must be on or before to');
    if (days.length > MAX_SUMMARY_DAYS) {
      throw new BadRequestException(`The range cannot exceed ${MAX_SUMMARY_DAYS} days`);
    }

    const inRange = { createdAt: { gte: start, lt: end } };
    const validOrders = { ...inRange, status: { not: OrderStatus.CANCELLED } };

    // A year of a small restaurant is a few tens of thousands of rows with two columns:
    // aggregating in the API keeps the time-zone logic in one tested place (no SQL date math)
    const [orders, dishes, payments, expenses] = await Promise.all([
      this.prisma.order.findMany({ where: validOrders, select: { createdAt: true, total: true } }),
      this.prisma.orderItem.groupBy({
        by: ['dishId', 'dishName'],
        where: { order: validOrders },
        _sum: { quantity: true, subtotal: true },
        orderBy: { _sum: { quantity: 'desc' } },
        take: 10,
      }),
      this.prisma.payment.groupBy({
        by: ['method'],
        where: inRange,
        _count: { _all: true },
        _sum: { amount: true },
      }),
      this.prisma.expense.groupBy({
        by: ['businessDate', 'category'],
        where: { businessDate: { gte: toDateColumn(from), lte: toDateColumn(to) }, isVoid: false },
        _sum: { amount: true },
      }),
    ]);

    return buildSummary({
      days,
      utcOffsetMinutes: this.utcOffsetMinutes,
      orders,
      dishes: dishes.map((row) => ({
        dishName: row.dishName,
        quantity: row._sum.quantity ?? 0,
        revenueCents: toCents(row._sum.subtotal),
      })),
      payments: payments.map((row) => ({
        method: row.method,
        count: row._count._all,
        amountCents: toCents(row._sum.amount),
      })),
      expenses: expenses.map((row) => ({
        date: fromDateColumn(row.businessDate),
        category: row.category,
        amountCents: toCents(row._sum.amount),
      })),
    });
  }
}
