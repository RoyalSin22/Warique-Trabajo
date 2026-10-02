// backend/src/orders/order-status.ts
import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { OrderStatus, Role } from '@prisma/client';

/**
 * Allowed transitions and who may perform each one.
 * PENDING -> IN_PREPARATION -> READY -> DELIVERED; CANCELLED from any open state.
 */
export const ORDER_TRANSITIONS: Record<OrderStatus, Partial<Record<OrderStatus, readonly Role[]>>> = {
  [OrderStatus.PENDING]: {
    [OrderStatus.IN_PREPARATION]: [Role.KITCHEN, Role.OWNER],
    [OrderStatus.CANCELLED]: [Role.WAITER, Role.OWNER],
  },
  [OrderStatus.IN_PREPARATION]: {
    [OrderStatus.READY]: [Role.KITCHEN, Role.OWNER],
    [OrderStatus.CANCELLED]: [Role.OWNER], // food already being cooked: owner decides
  },
  [OrderStatus.READY]: {
    [OrderStatus.DELIVERED]: [Role.WAITER, Role.OWNER],
    [OrderStatus.CANCELLED]: [Role.OWNER],
  },
  [OrderStatus.DELIVERED]: {},
  [OrderStatus.CANCELLED]: {},
};

export function assertTransitionAllowed(from: OrderStatus, to: OrderStatus, role: Role): void {
  const allowedRoles = ORDER_TRANSITIONS[from][to];
  if (!allowedRoles) {
    throw new BadRequestException(`Cannot change order status from ${from} to ${to}`);
  }
  if (!allowedRoles.includes(role)) {
    throw new ForbiddenException(`Role ${role} cannot change order status from ${from} to ${to}`);
  }
}
