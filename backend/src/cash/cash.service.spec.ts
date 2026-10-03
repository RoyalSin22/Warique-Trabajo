// backend/src/cash/cash.service.spec.ts
import { BadRequestException, ConflictException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CashService } from './cash.service';

describe('CashService', () => {
  const prisma = {
    cashSession: { findUnique: jest.fn(), upsert: jest.fn(), update: jest.fn() },
    payment: { aggregate: jest.fn() },
    expense: { aggregate: jest.fn() },
  };
  const service = new CashService(prisma as unknown as PrismaService, { get: () => -300 } as unknown as ConfigService);
  const owner = { id: 1, username: 'owner', fullName: 'Dueño', role: Role.OWNER };
  const date = '2026-10-02';

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.payment.aggregate.mockResolvedValue({ _sum: { amount: '250.40' } });
    prisma.expense.aggregate.mockResolvedValue({ _sum: { amount: '35.00' } });
  });

  it('computes the expected cash: fund + cash sales - cash expenses', async () => {
    prisma.cashSession.findUnique.mockResolvedValue({
      openingAmount: '100.00',
      businessDate: new Date('2026-10-02T00:00:00Z'),
      opener: { fullName: 'Dueño' },
      closer: null,
    });
    const day = await service.day(date);

    expect(day.live).toEqual({ openingAmount: '100.00', cashSales: '250.40', cashExpenses: '35.00', expected: '315.40' });
    expect(day.session).toMatchObject({ businessDate: date, openedByName: 'Dueño', closedByName: null });
    expect(prisma.payment.aggregate.mock.calls[0][0].where).toEqual({
      method: 'CASH',
      createdAt: { gte: new Date('2026-10-02T05:00:00.000Z'), lt: new Date('2026-10-03T05:00:00.000Z') },
    });
    expect(prisma.expense.aggregate.mock.calls[0][0].where).toEqual({
      businessDate: new Date('2026-10-02T00:00:00.000Z'),
      paidWith: 'CASH',
      isVoid: false,
    });
  });

  it('snapshots the difference when closing (negative = missing)', async () => {
    prisma.cashSession.findUnique.mockResolvedValue({
      openingAmount: '100.00',
      businessDate: new Date('2026-10-02T00:00:00Z'),
      opener: { fullName: 'Dueño' },
      closer: { fullName: 'Dueño' },
    });
    await service.close(date, 310.4, 'faltó vuelto', owner);

    expect(prisma.cashSession.update.mock.calls[0][0].data).toMatchObject({
      expectedAmount: '315.40',
      countedAmount: '310.40',
      difference: '-5.00',
      notes: 'faltó vuelto',
      closedBy: 1,
    });
  });

  it('requires opening before closing and blocks reopening a closed day', async () => {
    prisma.cashSession.findUnique.mockResolvedValue(null);
    await expect(service.close(date, 10, undefined, owner)).rejects.toThrow(ConflictException);

    prisma.cashSession.findUnique.mockResolvedValue({ closedAt: new Date() });
    await expect(service.open(date, 50, owner)).rejects.toThrow('already closed');
  });

  it('rejects future days', async () => {
    await expect(service.day('2999-01-01')).rejects.toThrow(BadRequestException);
  });
});
