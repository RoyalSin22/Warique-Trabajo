// backend/src/expenses/expenses.service.spec.ts
import { BadRequestException, ConflictException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpenseCategory, PaidWith, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { ExpensesService } from './expenses.service';

describe('ExpensesService', () => {
  const tx = {
    $queryRaw: jest.fn(),
    expense: { create: jest.fn(), findUniqueOrThrow: jest.fn(), update: jest.fn() },
    supplyMovement: { create: jest.fn() },
    supply: { update: jest.fn(({ where, data }) => ({ id: where.id, stock: data.stock })) },
  };
  const expenseRow = {
    id: 10,
    businessDate: new Date('2026-10-02T00:00:00Z'),
    creator: { fullName: 'Dueño' },
    items: [],
  };
  const prisma = {
    $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)),
    expense: { findUnique: jest.fn().mockResolvedValue(expenseRow), findMany: jest.fn() },
  };
  const realtime = { supplyUpdated: jest.fn() };
  const service = new ExpensesService(
    prisma as unknown as PrismaService,
    realtime as unknown as RealtimeService,
    { get: () => -300 } as unknown as ConfigService,
  );
  const owner = { id: 1, username: 'owner', fullName: 'Dueño', role: Role.OWNER };
  const purchase = {
    businessDate: '2026-10-02',
    category: ExpenseCategory.INSUMOS,
    description: 'Mercado',
    paidWith: PaidWith.CASH,
    items: [
      { supplyId: 2, quantity: 1.5, cost: 12.3 },
      { supplyId: 1, quantity: 10, cost: 8 },
    ],
  };

  beforeEach(() => {
    jest.clearAllMocks();
    tx.expense.create.mockResolvedValue({ id: 10 });
  });

  it('records a purchase with its total and adds each line to stock', async () => {
    tx.$queryRaw.mockResolvedValue([
      { id: 1, stock: '2.000', isActive: 1 },
      { id: 2, stock: '0.250', isActive: 1 },
    ]);
    const result = await service.create(purchase, owner);

    expect(tx.expense.create.mock.calls[0][0].data).toMatchObject({
      businessDate: new Date('2026-10-02T00:00:00.000Z'),
      amount: '20.30',
      items: { create: [{ supplyId: 2, quantity: '1.500', cost: '12.30' }, { supplyId: 1, quantity: '10.000', cost: '8.00' }] },
    });
    expect(tx.supply.update).toHaveBeenCalledWith({ where: { id: 2 }, data: { stock: '1.750' } });
    expect(tx.supply.update).toHaveBeenCalledWith({ where: { id: 1 }, data: { stock: '12.000' } });
    expect(tx.supplyMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ type: 'PURCHASE', expenseId: 10, quantity: '1.500' }),
    });
    expect(realtime.supplyUpdated).toHaveBeenCalledTimes(2);
    expect(result.businessDate).toBe('2026-10-02');
  });

  it('validates purchases before touching the database', async () => {
    const reject = (dto: object) => expect(service.create({ ...purchase, ...dto }, owner)).rejects.toThrow(BadRequestException);
    await reject({ category: ExpenseCategory.GAS });
    await reject({ amount: 99 });
    await reject({ items: [{ supplyId: 1, quantity: 1, cost: 1 }, { supplyId: 1, quantity: 2, cost: 1 }] });
    await reject({ items: [{ supplyId: 1, quantity: 1, cost: 0 }] });
    await reject({ items: [], amount: undefined });
    await reject({ businessDate: '2999-01-01' });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects inactive supplies inside the transaction', async () => {
    tx.$queryRaw.mockResolvedValue([{ id: 1, stock: '0', isActive: 0 }, { id: 2, stock: '0', isActive: 1 }]);
    await expect(service.create(purchase, owner)).rejects.toThrow('inactive');
    expect(tx.expense.create).not.toHaveBeenCalled();
  });

  it('voids a purchase by taking its stock back out', async () => {
    tx.$queryRaw
      .mockResolvedValueOnce([{ id: 10 }])
      .mockResolvedValueOnce([{ id: 1, stock: '12.000', isActive: 1 }]);
    tx.expense.findUniqueOrThrow.mockResolvedValue({ isVoid: false, items: [{ supplyId: 1, quantity: '10.000', supply: { name: 'Limón' } }] });

    await service.void(10, 'duplicado', owner);

    expect(tx.supplyMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ type: 'VOID', quantity: '-10.000', stockAfter: '2.000', note: 'duplicado' }),
    });
    expect(tx.expense.update).toHaveBeenCalledWith({ where: { id: 10 }, data: { isVoid: true, voidReason: 'duplicado' } });
  });

  it('refuses to void twice or below zero stock', async () => {
    tx.$queryRaw.mockResolvedValueOnce([{ id: 10 }]);
    tx.expense.findUniqueOrThrow.mockResolvedValueOnce({ isVoid: true, items: [] });
    await expect(service.void(10, 'x', owner)).rejects.toThrow(ConflictException);

    tx.$queryRaw.mockResolvedValueOnce([{ id: 10 }]).mockResolvedValueOnce([{ id: 1, stock: '3.000', isActive: 1 }]);
    tx.expense.findUniqueOrThrow.mockResolvedValueOnce({
      isVoid: false,
      items: [{ supplyId: 1, quantity: '10.000', supply: { name: 'Limón' } }],
    });
    await expect(service.void(10, 'x', owner)).rejects.toThrow('Limón has 3.000 left of the 10.000 bought');
    expect(tx.expense.update).not.toHaveBeenCalled();
  });

  it('lists the day with totals that skip voided expenses', async () => {
    prisma.expense.findMany.mockResolvedValue([
      { ...expenseRow, id: 3, amount: '10.00', paidWith: 'CASH', isVoid: false },
      { ...expenseRow, id: 2, amount: '5.50', paidWith: 'OTHER', isVoid: false },
      { ...expenseRow, id: 1, amount: '99.00', paidWith: 'CASH', isVoid: true },
    ]);
    const list = await service.list('2026-10-02');
    expect(list).toMatchObject({ total: '15.50', cashTotal: '10.00' });
    expect(list.expenses).toHaveLength(3);
  });
});
