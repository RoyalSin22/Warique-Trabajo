// backend/src/orders/orders.service.ts
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus, OrderType, PaymentStatus, Prisma, Role } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { businessDayRange } from '../common/utils/business-day';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import {
  AddOrderItemsDto,
  CancelOrderItemDto,
  CreateOrderDto,
  CreateOrderItemDto,
  ListOrdersQueryDto,
  UpdateOrderStatusDto,
} from './dto/order.dto';
import { ACTIVE_ITEM } from './active-item';
import { ACTIVE_PAYMENT } from './active-payment';
import { assertTransitionAllowed } from './order-status';

/** The kitchen still has it: new lines can join the same order. Afterwards: another order. */
const ITEMS_ADDABLE: OrderStatus[] = [OrderStatus.PENDING, OrderStatus.IN_PREPARATION];

const ORDER_LIST_INCLUDE = {
  table: { select: { id: true, label: true } },
  waiter: { select: { id: true, fullName: true } },
  items: {
    select: {
      id: true,
      dishId: true,
      dishName: true,
      unitPrice: true,
      quantity: true,
      subtotal: true,
      notes: true,
      addedAt: true,
      cancelledAt: true,
      cancelReason: true,
    },
    orderBy: { id: 'asc' },
  },
} as const;

/** Fields needed to validate a dish and snapshot it into an order item. */
interface OrderableDish {
  id: number;
  name: string;
  price: { toString(): string }; // Prisma.Decimal
  isActive: boolean;
  isAvailable: boolean;
  category: { isActive: boolean };
}

export const ORDER_DETAIL_INCLUDE = {
  ...ORDER_LIST_INCLUDE,
  payments: {
    select: {
      id: true,
      method: true,
      amount: true,
      amountReceived: true,
      changeGiven: true,
      operationNumber: true,
      createdAt: true,
      voidedAt: true,
      voidReason: true,
    },
    orderBy: { createdAt: 'asc' },
  },
} as const;

@Injectable()
export class OrdersService {
  private readonly utcOffsetMinutes: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    config: ConfigService,
  ) {
    this.utcOffsetMinutes = Number(config.get('BUSINESS_UTC_OFFSET_MINUTES') ?? -300);
  }

  /**
   * Orders of a business day. Without a date ("today"), orders from the previous two days that are
   * still open or unpaid are included too: an order left over from yesterday must not vanish from
   * the kitchen and the waiters when the day changes.
   */
  findAll(query: ListOrdersQueryDto) {
    const { start, end } = businessDayRange(query.date, this.utcOffsetMinutes);
    const sameDay: Prisma.OrderWhereInput = { createdAt: { gte: start, lt: end } };
    const leftOver: Prisma.OrderWhereInput = {
      createdAt: { gte: new Date(start.getTime() - 2 * 24 * 60 * 60 * 1000), lt: start },
      OR: [
        { status: { in: [OrderStatus.PENDING, OrderStatus.IN_PREPARATION, OrderStatus.READY] } },
        { status: OrderStatus.DELIVERED, paymentStatus: { not: PaymentStatus.PAID } },
      ],
    };
    return this.prisma.order.findMany({
      where: {
        ...(query.date ? sameDay : { OR: [sameDay, leftOver] }),
        ...(query.status?.length ? { status: { in: query.status } } : {}),
        ...(query.paymentStatus ? { paymentStatus: query.paymentStatus } : {}),
      },
      include: ORDER_LIST_INCLUDE, // single query with joins: no N+1
      orderBy: { createdAt: 'asc' }, // FIFO for the kitchen
    });
  }

  async findOne(id: number) {
    const order = await this.prisma.order.findUnique({ where: { id }, include: ORDER_DETAIL_INCLUDE });
    if (!order) throw new NotFoundException('Order not found');
    return order;
  }

  async create(dto: CreateOrderDto, waiter: AuthenticatedUser) {
    await this.assertValidTarget(dto);

    const { items, totalCents } = await this.snapshotItems(dto.items);

    const order = await this.prisma.order.create({
      data: {
        orderType: dto.orderType,
        tableId: dto.orderType === OrderType.DINE_IN ? dto.tableId! : null,
        customerName: dto.customerName,
        notes: dto.notes,
        waiterId: waiter.id,
        total: fromCents(totalCents),
        items: { create: items },
      },
      include: ORDER_DETAIL_INCLUDE,
    });

    this.realtime.orderCreated(order);
    return order;
  }

  /** Waiter or owner: more dishes for an order the kitchen has not finished (it sees them marked). */
  async addItems(id: number, dto: AddOrderItemsDto) {
    const { items } = await this.snapshotItems(dto.items);
    await this.prisma.$transaction(async (tx) => {
      const order = await this.lockOrder(tx, id);
      if (!ITEMS_ADDABLE.includes(order.status)) {
        throw new ConflictException('Items can only be added while the kitchen has the order');
      }
      const addedAt = new Date();
      await tx.orderItem.createMany({ data: items.map((item) => ({ ...item, orderId: id, addedAt })) });
      await this.recomputeTotals(tx, id);
    });
    return this.publish(id);
  }

  /**
   * Removes a line (or some of its units) with a reason. While the order is PENDING the waiter can
   * do it; once the kitchen started, only the owner. The line is kept, marked as removed.
   */
  async cancelItem(id: number, itemId: number, dto: CancelOrderItemDto, actor: AuthenticatedUser) {
    await this.prisma.$transaction(async (tx) => {
      const order = await this.lockOrder(tx, id);
      if (order.status === OrderStatus.CANCELLED) throw new ConflictException('The order is cancelled');
      if (order.status !== OrderStatus.PENDING && actor.role !== Role.OWNER) {
        throw new ForbiddenException('Only the owner can remove items the kitchen already started');
      }

      const item = await tx.orderItem.findFirst({ where: { id: itemId, orderId: id } });
      if (!item) throw new NotFoundException('Item not found');
      if (item.cancelledAt) throw new ConflictException('The item is already removed');
      const quantity = dto.quantity ?? item.quantity;
      if (quantity > item.quantity) throw new BadRequestException('Cannot remove more units than ordered');

      const active = await tx.orderItem.aggregate({ where: { orderId: id, ...ACTIVE_ITEM }, _sum: { quantity: true } });
      if ((active._sum.quantity ?? 0) - quantity <= 0) {
        throw new ConflictException('Cannot remove the last item: cancel the order instead');
      }

      const cancelled = { cancelledAt: new Date(), cancelledBy: actor.id, cancelReason: dto.reason };
      if (quantity === item.quantity) {
        await tx.orderItem.update({ where: { id: itemId }, data: cancelled });
      } else {
        // Some units only: the line keeps the rest and a removed twin records the units taken out
        await tx.orderItem.update({ where: { id: itemId }, data: { quantity: item.quantity - quantity } });
        await tx.orderItem.create({
          data: {
            orderId: id,
            dishId: item.dishId,
            dishName: item.dishName,
            unitPrice: item.unitPrice,
            quantity,
            notes: item.notes,
            addedAt: item.addedAt,
            ...cancelled,
          },
        });
      }
      await this.recomputeTotals(tx, id);
    });
    return this.publish(id);
  }

  async updateStatus(id: number, dto: UpdateOrderStatusDto, actor: AuthenticatedUser) {
    const order = await this.prisma.order.findUnique({
      where: { id },
      select: { status: true, paymentStatus: true, waiterId: true },
    });
    if (!order) throw new NotFoundException('Order not found');

    assertTransitionAllowed(order.status, dto.status, actor.role);

    const isCancel = dto.status === OrderStatus.CANCELLED;
    // Another waiter's order is theirs to cancel (or the owner's), never a colleague's by mistake
    if (isCancel && actor.role === Role.WAITER && order.waiterId !== actor.id) {
      throw new ForbiddenException('Only the waiter who took the order or the owner can cancel it');
    }
    if (isCancel && !dto.cancelReason) {
      throw new BadRequestException('cancelReason is required to cancel an order');
    }
    if (isCancel && order.paymentStatus !== PaymentStatus.UNPAID) {
      throw new ConflictException('Cannot cancel an order that already has payments');
    }

    // Optimistic concurrency: only applies if nobody changed the order since we read it
    const { count } = await this.prisma.order.updateMany({
      where: {
        id,
        status: order.status,
        ...(isCancel ? { paymentStatus: PaymentStatus.UNPAID } : {}),
      },
      data: { status: dto.status, ...(isCancel ? { cancelReason: dto.cancelReason } : {}) },
    });
    if (count === 0) {
      throw new ConflictException('The order was modified by someone else. Reload and try again');
    }

    const updated = await this.findOne(id);
    this.realtime.orderUpdated(updated);
    return updated;
  }

  /** Validates availability and copies name and price, so later menu changes never alter the order. */
  private async snapshotItems(requested: CreateOrderItemDto[]) {
    const dishIds = [...new Set(requested.map((item) => item.dishId))];
    const dishes = await this.prisma.dish.findMany({
      where: { id: { in: dishIds } },
      select: {
        id: true,
        name: true,
        price: true,
        isActive: true,
        isAvailable: true,
        category: { select: { isActive: true } },
      },
    });
    const dishById = new Map<number, OrderableDish>(dishes.map((dish: OrderableDish) => [dish.id, dish]));

    const unavailableIds = dishIds.filter((dishId) => {
      const dish = dishById.get(dishId);
      return !dish || !dish.isActive || !dish.isAvailable || !dish.category.isActive;
    });
    if (unavailableIds.length > 0) {
      throw new BadRequestException({
        message: 'Some dishes are not available',
        unavailableDishIds: unavailableIds,
      });
    }

    let totalCents = 0;
    const items = requested.map((item) => {
      const dish = dishById.get(item.dishId)!;
      const unitCents = toCents(dish.price);
      totalCents += unitCents * item.quantity;
      return {
        dishId: dish.id,
        dishName: dish.name,
        unitPrice: fromCents(unitCents),
        quantity: item.quantity,
        notes: item.notes,
      };
    });
    return { items, totalCents };
  }

  /** Same row lock as payments: edits and payments of one order never interleave. */
  private async lockOrder(tx: Prisma.TransactionClient, id: number) {
    const locked = await tx.$queryRaw<{ id: number }[]>`SELECT id FROM orders WHERE id = ${id} FOR UPDATE`;
    if (locked.length === 0) throw new NotFoundException('Order not found');
    return tx.order.findUniqueOrThrow({ where: { id }, select: { status: true } });
  }

  /** Total = active lines; payment status follows. Refuses to go below what was already paid. */
  private async recomputeTotals(tx: Prisma.TransactionClient, id: number): Promise<void> {
    const lines = await tx.orderItem.findMany({
      where: { orderId: id, ...ACTIVE_ITEM },
      select: { unitPrice: true, quantity: true },
    });
    const totalCents = lines.reduce((sum, line) => sum + toCents(line.unitPrice) * line.quantity, 0);
    const paid = await tx.payment.aggregate({ where: { orderId: id, ...ACTIVE_PAYMENT }, _sum: { amount: true } });
    const paidCents = toCents(paid._sum.amount);
    if (paidCents > totalCents) {
      throw new ConflictException('The order would be below what was already paid: void a payment first');
    }
    const fullyPaid = paidCents > 0 && paidCents === totalCents;
    const current = await tx.order.findUniqueOrThrow({ where: { id }, select: { paidAt: true } });
    await tx.order.update({
      where: { id },
      data: {
        total: fromCents(totalCents),
        paymentStatus: fullyPaid ? PaymentStatus.PAID : paidCents > 0 ? PaymentStatus.PARTIAL : PaymentStatus.UNPAID,
        paidAt: fullyPaid ? (current.paidAt ?? new Date()) : null,
      },
    });
  }

  private async publish(id: number) {
    const updated = await this.findOne(id);
    this.realtime.orderUpdated(updated);
    return updated;
  }

  private async assertValidTarget(dto: CreateOrderDto): Promise<void> {
    if (dto.orderType === OrderType.TAKEAWAY) {
      if (dto.tableId !== undefined) {
        throw new BadRequestException('Takeaway orders cannot have a table');
      }
      return;
    }

    if (dto.tableId === undefined) {
      throw new BadRequestException('Dine-in orders require a tableId');
    }
    const table = await this.prisma.diningTable.findUnique({
      where: { id: dto.tableId },
      select: { isActive: true },
    });
    if (!table?.isActive) {
      throw new BadRequestException('Table does not exist or is inactive');
    }
  }
}
