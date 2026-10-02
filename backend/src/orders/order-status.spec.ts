// backend/src/orders/order-status.spec.ts
import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { OrderStatus as S, Role as R } from '@prisma/client';
import { assertTransitionAllowed } from './order-status';

describe('assertTransitionAllowed', () => {
  it.each([
    [S.PENDING, S.IN_PREPARATION, R.KITCHEN],
    [S.IN_PREPARATION, S.READY, R.KITCHEN],
    [S.READY, S.DELIVERED, R.WAITER],
    [S.PENDING, S.CANCELLED, R.WAITER],
    [S.READY, S.CANCELLED, R.OWNER],
  ])('allows %s -> %s for %s', (from, to, role) => {
    expect(() => assertTransitionAllowed(from, to, role)).not.toThrow();
  });

  it.each([
    [S.PENDING, S.READY], // skipping a step
    [S.READY, S.PENDING], // going backwards
    [S.DELIVERED, S.CANCELLED], // final state
    [S.CANCELLED, S.PENDING], // final state
  ])('rejects invalid transition %s -> %s', (from, to) => {
    expect(() => assertTransitionAllowed(from, to, R.OWNER)).toThrow(BadRequestException);
  });

  it.each([
    [S.PENDING, S.IN_PREPARATION, R.WAITER],
    [S.READY, S.DELIVERED, R.KITCHEN],
    [S.IN_PREPARATION, S.CANCELLED, R.WAITER],
    [S.PENDING, S.CANCELLED, R.KITCHEN],
  ])('forbids %s -> %s for %s', (from, to, role) => {
    expect(() => assertTransitionAllowed(from, to, role)).toThrow(ForbiddenException);
  });
});
