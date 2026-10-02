// backend/src/orders/orders.service.ts
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus, OrderType, PaymentStatus } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { businessDayRange } from '../common/utils/business-day';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { CreateOrderDto, ListOrdersQueryDto, UpdateOrderStatusDto } from './dto/order.dto';
import { assertTransitionAllowed } from './order-status';

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
    },
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

  findAll(query: ListOrdersQueryDto) {
    const { start, end } = businessDayRange(query.date, this.utcOffsetMinutes);
    return this.prisma.order.findMany({
      where: {
        createdAt: { gte: start, lt: end },
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

    const dishIds = [...new Set(dto.items.map((item) => item.dishId))];
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
    const dishById = new Map<number, OrderableDish>(
      dishes.map((dish: OrderableDish) => [dish.id, dish]),
    );

    const unavailableIds = dishIds.filter((id) => {
      const dish = dishById.get(id);
      return !dish || !dish.isActive || !dish.isAvailable || !dish.category.isActive;
    });
    if (unavailableIds.length > 0) {
      throw new BadRequestException({
        message: 'Some dishes are not available',
        unavailableDishIds: unavailableIds,
      });
    }

    // Name and price are copied (snapshot) so later menu changes never alter this order
    let totalCents = 0;
    const items = dto.items.map((item) => {
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

  async updateStatus(id: number, dto: UpdateOrderStatusDto, actor: AuthenticatedUser) {
    const order = await this.prisma.order.findUnique({
      where: { id },
      select: { status: true, paymentStatus: true },
    });
    if (!order) throw new NotFoundException('Order not found');

    assertTransitionAllowed(order.status, dto.status, actor.role);

    const isCancel = dto.status === OrderStatus.CANCELLED;
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
