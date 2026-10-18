// backend/src/orders/orders.service.spec.ts
import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus, OrderType, PaymentStatus, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { OrdersService } from './orders.service';

describe('OrdersService', () => {
  const prisma = {
    diningTable: { findUnique: jest.fn() },
    dish: { findMany: jest.fn() },
    order: { create: jest.fn(), findUnique: jest.fn(), updateMany: jest.fn() },
    $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)),
  };
  const tx = {
    $queryRaw: jest.fn(),
    order: { findUniqueOrThrow: jest.fn(), update: jest.fn() },
    orderItem: {
      createMany: jest.fn(),
      findFirst: jest.fn(),
      aggregate: jest.fn(),
      update: jest.fn(),
      create: jest.fn(),
      findMany: jest.fn(),
    },
    payment: { aggregate: jest.fn() },
  };
  const realtime = { orderCreated: jest.fn(), orderUpdated: jest.fn() };
  const config = { get: jest.fn().mockReturnValue(-300) };
  const service = new OrdersService(
    prisma as unknown as PrismaService,
    realtime as unknown as RealtimeService,
    config as unknown as ConfigService,
  );
  const waiter = { id: 7, username: 'ana', fullName: 'Ana', role: Role.WAITER };
  const kitchen = { id: 8, username: 'luis', fullName: 'Luis', role: Role.KITCHEN };
  const dish = (id: number, name: string, price: string, overrides = {}) => ({
    id, name, price, isActive: true, isAvailable: true, category: { isActive: true }, ...overrides,
  });

  beforeEach(() => jest.clearAllMocks());

  describe('create', () => {
    it('snapshots name/price and computes the total in cents', async () => {
      prisma.dish.findMany.mockResolvedValue([dish(1, 'Ceviche', '18.50'), dish(2, 'Chicha', '3.00')]);
      prisma.order.create.mockResolvedValue({ id: 5 });

      await service.create(
        {
          orderType: OrderType.TAKEAWAY,
          items: [{ dishId: 1, quantity: 2 }, { dishId: 2, quantity: 1, notes: 'helada' }],
        },
        waiter,
      );

      const { data } = prisma.order.create.mock.calls[0][0];
      expect(data.total).toBe('40.00');
      expect(data.waiterId).toBe(7);
      expect(data.tableId).toBeNull();
      expect(data.items.create).toEqual([
        { dishId: 1, dishName: 'Ceviche', unitPrice: '18.50', quantity: 2, notes: undefined },
        { dishId: 2, dishName: 'Chicha', unitPrice: '3.00', quantity: 1, notes: 'helada' },
      ]);
      expect(realtime.orderCreated).toHaveBeenCalledWith({ id: 5 });
    });

    it('rejects sold-out, inactive or missing dishes', async () => {
      prisma.dish.findMany.mockResolvedValue([dish(1, 'Ceviche', '18.50', { isAvailable: false })]);

      await expect(
        service.create(
          { orderType: OrderType.TAKEAWAY, items: [{ dishId: 1, quantity: 1 }, { dishId: 99, quantity: 1 }] },
          waiter,
        ),
      ).rejects.toThrow(BadRequestException);
      expect(prisma.order.create).not.toHaveBeenCalled();
    });

    it('requires a table for dine-in orders', async () => {
      await expect(
        service.create({ orderType: OrderType.DINE_IN, items: [{ dishId: 1, quantity: 1 }] }, waiter),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a table on takeaway orders', async () => {
      await expect(
        service.create(
          { orderType: OrderType.TAKEAWAY, tableId: 3, items: [{ dishId: 1, quantity: 1 }] },
          waiter,
        ),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects an inactive table', async () => {
      prisma.diningTable.findUnique.mockResolvedValue({ isActive: false });
      await expect(
        service.create(
          { orderType: OrderType.DINE_IN, tableId: 3, items: [{ dishId: 1, quantity: 1 }] },
          waiter,
        ),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('updateStatus', () => {
    it('applies a valid transition with optimistic locking', async () => {
      prisma.order.findUnique
        .mockResolvedValueOnce({ status: OrderStatus.PENDING, paymentStatus: PaymentStatus.UNPAID })
        .mockResolvedValueOnce({ id: 1, status: OrderStatus.IN_PREPARATION });
      prisma.order.updateMany.mockResolvedValue({ count: 1 });

      await service.updateStatus(1, { status: OrderStatus.IN_PREPARATION }, kitchen);

      expect(prisma.order.updateMany).toHaveBeenCalledWith({
        where: { id: 1, status: OrderStatus.PENDING },
        data: { status: OrderStatus.IN_PREPARATION },
      });
      expect(realtime.orderUpdated).toHaveBeenCalled();
    });

    it('returns 409 when someone else changed the order first', async () => {
      prisma.order.findUnique.mockResolvedValue({ status: OrderStatus.PENDING, paymentStatus: PaymentStatus.UNPAID });
      prisma.order.updateMany.mockResolvedValue({ count: 0 });

      await expect(
        service.updateStatus(1, { status: OrderStatus.IN_PREPARATION }, kitchen),
      ).rejects.toThrow(ConflictException);
    });

    it('requires a reason to cancel', async () => {
      prisma.order.findUnique.mockResolvedValue({ status: OrderStatus.PENDING, paymentStatus: PaymentStatus.UNPAID });
      await expect(
        service.updateStatus(1, { status: OrderStatus.CANCELLED }, waiter),
      ).rejects.toThrow(BadRequestException);
    });

    it('refuses to cancel an order with payments', async () => {
      prisma.order.findUnique.mockResolvedValue({ status: OrderStatus.PENDING, paymentStatus: PaymentStatus.PARTIAL });
      await expect(
        service.updateStatus(1, { status: OrderStatus.CANCELLED, cancelReason: 'cliente se fue' }, waiter),
      ).rejects.toThrow(ConflictException);
      expect(prisma.order.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('editing a sent order', () => {
    const owner = { id: 1, username: 'dueno', fullName: 'Dueño', role: Role.OWNER };
    const line = { id: 20, dishId: 1, dishName: 'Ceviche', unitPrice: '18.50', quantity: 2, notes: null, addedAt: null, cancelledAt: null };

    /** status of the order, active lines after the change, and what was already paid */
    const given = (status: OrderStatus, linesAfter: { unitPrice: string; quantity: number }[], paid: string | null = null) => {
      tx.$queryRaw.mockResolvedValue([{ id: 5 }]);
      tx.order.findUniqueOrThrow.mockResolvedValue({ status, paidAt: null });
      tx.orderItem.findMany.mockResolvedValue(linesAfter);
      tx.payment.aggregate.mockResolvedValue({ _sum: { amount: paid } });
      tx.orderItem.findFirst.mockResolvedValue(line);
      tx.orderItem.aggregate.mockResolvedValue({ _sum: { quantity: 3 } });
      prisma.order.findUnique.mockResolvedValue({ id: 5 });
    };

    it('adds marked lines while the kitchen has the order and recomputes the total', async () => {
      prisma.dish.findMany.mockResolvedValue([dish(2, 'Chicha', '3.00')]);
      given(OrderStatus.IN_PREPARATION, [{ unitPrice: '18.50', quantity: 2 }, { unitPrice: '3.00', quantity: 1 }], '37.00');

      await service.addItems(5, { items: [{ dishId: 2, quantity: 1 }] });

      const { data } = tx.orderItem.createMany.mock.calls[0][0];
      expect(data).toEqual([expect.objectContaining({ orderId: 5, dishName: 'Chicha', addedAt: expect.any(Date) })]);
      expect(tx.order.update).toHaveBeenCalledWith({
        where: { id: 5 },
        data: { total: '40.00', paymentStatus: PaymentStatus.PARTIAL, paidAt: null },
      });
      expect(realtime.orderUpdated).toHaveBeenCalled();
    });

    it('refuses to add once the order is ready: that is another order', async () => {
      prisma.dish.findMany.mockResolvedValue([dish(2, 'Chicha', '3.00')]);
      given(OrderStatus.READY, []);
      await expect(service.addItems(5, { items: [{ dishId: 2, quantity: 1 }] })).rejects.toThrow(ConflictException);
      expect(tx.orderItem.createMany).not.toHaveBeenCalled();
    });

    it('lets the waiter remove a line while the order is pending', async () => {
      given(OrderStatus.PENDING, [{ unitPrice: '3.00', quantity: 1 }]);
      await service.cancelItem(5, 20, { reason: 'se acabó' }, waiter);
      expect(tx.orderItem.update).toHaveBeenCalledWith({
        where: { id: 20 },
        data: { cancelledAt: expect.any(Date), cancelledBy: 7, cancelReason: 'se acabó' },
      });
      expect(tx.order.update.mock.calls[0][0].data.total).toBe('3.00');
    });

    it('once the kitchen started, only the owner removes items', async () => {
      given(OrderStatus.IN_PREPARATION, []);
      await expect(service.cancelItem(5, 20, { reason: 'se acabó' }, waiter)).rejects.toThrow(ForbiddenException);
      await expect(service.cancelItem(5, 20, { reason: 'se acabó' }, kitchen)).rejects.toThrow(ForbiddenException);
      expect(tx.orderItem.update).not.toHaveBeenCalled();

      given(OrderStatus.IN_PREPARATION, [{ unitPrice: '3.00', quantity: 1 }]);
      await service.cancelItem(5, 20, { reason: 'se acabó' }, owner);
      expect(tx.orderItem.update).toHaveBeenCalled();
    });

    it('removing some units keeps the rest and records a removed twin', async () => {
      given(OrderStatus.PENDING, [{ unitPrice: '18.50', quantity: 1 }]);
      await service.cancelItem(5, 20, { reason: 'solo uno', quantity: 1 }, waiter);
      expect(tx.orderItem.update).toHaveBeenCalledWith({ where: { id: 20 }, data: { quantity: 1 } });
      expect(tx.orderItem.create.mock.calls[0][0].data).toMatchObject({
        orderId: 5, dishName: 'Ceviche', quantity: 1, cancelledBy: 7, cancelReason: 'solo uno',
      });
    });

    it('never removes the last item, nor goes below what was paid', async () => {
      given(OrderStatus.PENDING, []);
      tx.orderItem.aggregate.mockResolvedValue({ _sum: { quantity: 2 } });
      await expect(service.cancelItem(5, 20, { reason: 'x x' }, waiter)).rejects.toThrow('cancel the order instead');

      given(OrderStatus.PENDING, [{ unitPrice: '3.00', quantity: 1 }], '20.00');
      await expect(service.cancelItem(5, 20, { reason: 'x x' }, waiter)).rejects.toThrow('void a payment first');
    });
  });
});
