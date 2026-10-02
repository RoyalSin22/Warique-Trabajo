// backend/src/reports/reports.service.spec.ts
import { ConfigService } from '@nestjs/config';
import { OrderStatus, PaymentMethod } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ReportsService } from './reports.service';

describe('ReportsService.daily', () => {
  const prisma = {
    order: { groupBy: jest.fn() },
    payment: { groupBy: jest.fn(), aggregate: jest.fn() },
    orderItem: { groupBy: jest.fn() },
  };
  const service = new ReportsService(
    prisma as unknown as PrismaService,
    { get: () => -300 } as unknown as ConfigService,
  );

  it('excludes cancelled orders from sales and computes the pending balance', async () => {
    prisma.order.groupBy.mockResolvedValue([
      { status: OrderStatus.DELIVERED, _count: { _all: 3 }, _sum: { total: '90.50' } },
      { status: OrderStatus.PENDING, _count: { _all: 1 }, _sum: { total: '20.00' } },
      { status: OrderStatus.CANCELLED, _count: { _all: 1 }, _sum: { total: '15.00' } },
    ]);
    prisma.payment.groupBy.mockResolvedValue([
      { method: PaymentMethod.CASH, _count: { _all: 2 }, _sum: { amount: '50.50' } },
      { method: PaymentMethod.YAPE, _count: { _all: 1 }, _sum: { amount: '40.00' } },
    ]);
    prisma.payment.aggregate.mockResolvedValue({ _sum: { amount: '90.50' } });
    prisma.orderItem.groupBy.mockResolvedValue([
      { dishId: 1, dishName: 'Ceviche', _sum: { quantity: 5 } },
    ]);

    const report = await service.daily('2026-10-02');

    expect(report.sales).toBe('110.50');
    expect(report.collectedTotal).toBe('90.50');
    expect(report.pendingBalance).toBe('20.00');
    expect(report.topDishes).toEqual([{ dishId: 1, dishName: 'Ceviche', quantity: 5 }]);
  });
});
