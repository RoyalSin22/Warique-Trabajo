// backend/src/reports/reports.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus } from '@prisma/client';
import { businessDayRange } from '../common/utils/business-day';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';

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

    // Four aggregate queries in parallel; the database does the summing
    const [ordersByStatus, paymentsByMethod, topDishes, paidOnDayOrders] = await Promise.all([
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
    ]);

    const salesCents = ordersByStatus
      .filter((row) => row.status !== OrderStatus.CANCELLED)
      .reduce((sum, row) => sum + toCents(row._sum.total), 0);
    const collectedCents = paymentsByMethod.reduce((sum, row) => sum + toCents(row._sum.amount), 0);

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
    };
  }
}
