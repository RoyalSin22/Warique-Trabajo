// backend/src/orders/payments.service.spec.ts
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { OrderStatus, PaymentMethod, PaymentStatus, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { OrdersService } from './orders.service';
import { PaymentsService } from './payments.service';

describe('PaymentsService', () => {
  const tx = {
    $queryRaw: jest.fn(),
    order: { findUniqueOrThrow: jest.fn(), update: jest.fn() },
    payment: { aggregate: jest.fn(), create: jest.fn() },
  };
  const prisma = { $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)) };
  const ordersService = { findOne: jest.fn().mockResolvedValue({ id: 1 }) };
  const realtime = { orderUpdated: jest.fn() };
  const service = new PaymentsService(
    prisma as unknown as PrismaService,
    ordersService as unknown as OrdersService,
    realtime as unknown as RealtimeService,
  );
  const waiter = { id: 7, username: 'ana', fullName: 'Ana', role: Role.WAITER };

  interface OrderFixture {
    status?: OrderStatus;
    paymentStatus?: PaymentStatus;
    total?: string;
    alreadyPaid?: string | null;
  }

  const givenOrder = ({
    status = OrderStatus.DELIVERED,
    paymentStatus = PaymentStatus.UNPAID,
    total = '40.00',
    alreadyPaid = null,
  }: OrderFixture = {}) => {
    tx.$queryRaw.mockResolvedValue([{ id: 1 }]);
    tx.order.findUniqueOrThrow.mockResolvedValue({ status, paymentStatus, total });
    tx.payment.aggregate.mockResolvedValue({ _sum: { amount: alreadyPaid } });
  };

  beforeEach(() => jest.clearAllMocks());

  it('marks the order PAID when cash covers the total', async () => {
    givenOrder();
    await service.register(1, { method: PaymentMethod.CASH, amount: 40, amountReceived: 50 }, waiter);

    expect(tx.payment.create).toHaveBeenCalledWith({
      data: {
        orderId: 1,
        method: PaymentMethod.CASH,
        amount: '40.00',
        amountReceived: '50.00',
        operationNumber: null,
        registeredBy: 7,
      },
    });
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 1 },
      data: { paymentStatus: PaymentStatus.PAID, paidAt: expect.any(Date) },
    });
    expect(realtime.orderUpdated).toHaveBeenCalled();
  });

  it('marks the order PARTIAL on a split payment', async () => {
    givenOrder();
    await service.register(1, { method: PaymentMethod.YAPE, amount: 15, operationNumber: '123456' }, waiter);

    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 1 },
      data: { paymentStatus: PaymentStatus.PARTIAL, paidAt: null },
    });
  });

  it('completes the order after a previous partial payment', async () => {
    givenOrder({ paymentStatus: PaymentStatus.PARTIAL, alreadyPaid: '15.00' });
    await service.register(1, { method: PaymentMethod.PLIN, amount: 25, operationNumber: 'AB-9876' }, waiter);

    expect(tx.order.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ paymentStatus: PaymentStatus.PAID }) }),
    );
  });

  it('rejects an amount above the pending balance', async () => {
    givenOrder({ paymentStatus: PaymentStatus.PARTIAL, alreadyPaid: '30.00' });
    await expect(
      service.register(1, { method: PaymentMethod.CASH, amount: 20, amountReceived: 20 }, waiter),
    ).rejects.toThrow(BadRequestException);
    expect(tx.payment.create).not.toHaveBeenCalled();
  });

  it('rejects payments on cancelled orders', async () => {
    givenOrder({ status: OrderStatus.CANCELLED });
    await expect(
      service.register(1, { method: PaymentMethod.CASH, amount: 10, amountReceived: 10 }, waiter),
    ).rejects.toThrow(ConflictException);
  });

  it('returns 404 when the order does not exist', async () => {
    tx.$queryRaw.mockResolvedValue([]);
    await expect(
      service.register(99, { method: PaymentMethod.CASH, amount: 10, amountReceived: 10 }, waiter),
    ).rejects.toThrow(NotFoundException);
  });

  it('requires amountReceived >= amount for cash, before opening a transaction', async () => {
    await expect(
      service.register(1, { method: PaymentMethod.CASH, amount: 40, amountReceived: 20 }, waiter),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('requires the operation number for Yape/Plin', async () => {
    await expect(
      service.register(1, { method: PaymentMethod.YAPE, amount: 10 }, waiter),
    ).rejects.toThrow(BadRequestException);
  });
});
