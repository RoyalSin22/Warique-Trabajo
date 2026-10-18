// backend/src/orders/payments.service.ts
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus, PaymentMethod, PaymentStatus } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { ACTIVE_PAYMENT } from './active-payment';
import { CreatePaymentDto } from './dto/payment.dto';
import { OrdersService } from './orders.service';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ordersService: OrdersService,
    private readonly realtime: RealtimeService,
  ) {}

  async register(orderId: number, dto: CreatePaymentDto, actor: AuthenticatedUser) {
    this.assertMethodFields(dto);
    const amountCents = toCents(dto.amount);

    await this.prisma.$transaction(async (tx) => {
      // Row lock (InnoDB): concurrent payments for the same order wait here,
      // so two waiters can never overpay the same order.
      const locked = await tx.$queryRaw<{ id: number }[]>`
        SELECT id FROM orders WHERE id = ${orderId} FOR UPDATE`;
      if (locked.length === 0) throw new NotFoundException('Order not found');

      const order = await tx.order.findUniqueOrThrow({
        where: { id: orderId },
        select: { status: true, paymentStatus: true, total: true },
      });
      if (order.status === OrderStatus.CANCELLED) {
        throw new ConflictException('Cannot register a payment for a cancelled order');
      }
      if (order.paymentStatus === PaymentStatus.PAID) {
        throw new ConflictException('The order is already paid');
      }

      const paid = await tx.payment.aggregate({ where: { orderId, ...ACTIVE_PAYMENT }, _sum: { amount: true } });
      const totalCents = toCents(order.total);
      const paidCents = toCents(paid._sum.amount);
      const balanceCents = totalCents - paidCents;

      if (amountCents > balanceCents) {
        throw new BadRequestException(
          `Amount exceeds the pending balance of S/ ${fromCents(balanceCents)}`,
        );
      }

      const isCash = dto.method === PaymentMethod.CASH;
      await tx.payment.create({
        data: {
          orderId,
          method: dto.method,
          amount: fromCents(amountCents),
          amountReceived: isCash ? fromCents(toCents(dto.amountReceived)) : null,
          operationNumber: isCash ? null : dto.operationNumber,
          registeredBy: actor.id,
        },
      });

      const fullyPaid = paidCents + amountCents === totalCents;
      await tx.order.update({
        where: { id: orderId },
        data: {
          paymentStatus: fullyPaid ? PaymentStatus.PAID : PaymentStatus.PARTIAL,
          paidAt: fullyPaid ? new Date() : null,
        },
      });
    });

    const updated = await this.ordersService.findOne(orderId);
    this.realtime.orderUpdated(updated);
    return updated;
  }

  /**
   * Owner only: undoes a payment registered by mistake (wrong method, amount or order).
   * The row is kept with who/when/why; the order's payment status is recomputed from the rest.
   */
  async void(orderId: number, paymentId: number, reason: string, actor: AuthenticatedUser) {
    await this.prisma.$transaction(async (tx) => {
      // Same lock as register(): a payment being added meanwhile waits, so the status stays right
      const locked = await tx.$queryRaw<{ id: number }[]>`
        SELECT id FROM orders WHERE id = ${orderId} FOR UPDATE`;
      if (locked.length === 0) throw new NotFoundException('Order not found');

      const payment = await tx.payment.findFirst({
        where: { id: paymentId, orderId },
        select: { voidedAt: true },
      });
      if (!payment) throw new NotFoundException('Payment not found');
      if (payment.voidedAt) throw new ConflictException('The payment is already void');

      await tx.payment.update({
        where: { id: paymentId },
        data: { voidedAt: new Date(), voidedBy: actor.id, voidReason: reason },
      });

      const order = await tx.order.findUniqueOrThrow({ where: { id: orderId }, select: { total: true } });
      const paid = await tx.payment.aggregate({ where: { orderId, ...ACTIVE_PAYMENT }, _sum: { amount: true } });
      const paidCents = toCents(paid._sum.amount);
      const fullyPaid = paidCents > 0 && paidCents === toCents(order.total);
      await tx.order.update({
        where: { id: orderId },
        data: {
          paymentStatus: fullyPaid ? PaymentStatus.PAID : paidCents > 0 ? PaymentStatus.PARTIAL : PaymentStatus.UNPAID,
          ...(fullyPaid ? {} : { paidAt: null }),
        },
      });
    });

    const updated = await this.ordersService.findOne(orderId);
    this.realtime.orderUpdated(updated);
    return updated;
  }

  private assertMethodFields(dto: CreatePaymentDto): void {
    if (dto.method === PaymentMethod.CASH) {
      if (dto.operationNumber !== undefined) {
        throw new BadRequestException('Cash payments do not have an operation number');
      }
      if (dto.amountReceived === undefined || toCents(dto.amountReceived) < toCents(dto.amount)) {
        throw new BadRequestException('Cash payments require amountReceived >= amount');
      }
      return;
    }

    if (dto.amountReceived !== undefined) {
      throw new BadRequestException('amountReceived only applies to cash payments');
    }
    if (!dto.operationNumber) {
      throw new BadRequestException('Yape/Plin payments require the operation number');
    }
  }
}
