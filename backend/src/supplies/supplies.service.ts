// backend/src/supplies/supplies.service.ts
import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { MovementType, Prisma } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { fromMilli, toMilli } from '../common/utils/quantity';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { CreateMovementDto, CreateSupplyDto, UpdateSupplyDto } from './dto/supply.dto';

type Tx = Prisma.TransactionClient;

const MOVEMENT_SELECT = {
  id: true,
  type: true,
  quantity: true,
  stockAfter: true,
  expenseId: true,
  note: true,
  createdAt: true,
  creator: { select: { fullName: true } },
} as const;

@Injectable()
export class SuppliesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  /** Low stock first, so the kitchen sees what to buy without scrolling. */
  async findAll(includeInactive: boolean) {
    const supplies = await this.prisma.supply.findMany({
      where: includeInactive ? {} : { isActive: true },
      orderBy: { name: 'asc' },
    });
    return supplies
      .map((supply) => ({ ...supply, isLow: isLow(supply) }))
      .sort((a, b) => Number(b.isLow) - Number(a.isLow));
  }

  async create(dto: CreateSupplyDto) {
    const supply = await this.prisma.supply.create({
      data: { name: dto.name, unit: dto.unit, minStock: fromMilli(toMilli(dto.minStock)) },
    });
    return this.publish(supply);
  }

  /** No DELETE: deactivate with { isActive: false } so purchase history stays intact. */
  async update(id: number, dto: UpdateSupplyDto) {
    const supply = await this.prisma.supply.update({
      where: { id },
      data: {
        ...dto,
        ...(dto.minStock !== undefined ? { minStock: fromMilli(toMilli(dto.minStock)) } : {}),
      },
    });
    return this.publish(supply);
  }

  async movements(id: number) {
    const supply = await this.prisma.supply.findUnique({ where: { id } });
    if (!supply) throw new NotFoundException('Supply not found');
    const rows = await this.prisma.supplyMovement.findMany({
      where: { supplyId: id },
      select: MOVEMENT_SELECT,
      orderBy: { id: 'desc' },
      take: 100,
    });
    return {
      supply: { ...supply, isLow: isLow(supply) },
      movements: rows.map(({ creator, ...row }) => ({ ...row, createdBy: creator.fullName })),
    };
  }

  /**
   * COUNT sets the stock to what was counted (the difference is recorded as the movement);
   * WASTE and USE subtract. Stock never goes below zero: the kitchen counts first instead.
   */
  async addMovement(id: number, dto: CreateMovementDto, actor: AuthenticatedUser) {
    const quantityMilli = toMilli(dto.quantity);
    if (dto.type !== MovementType.COUNT && quantityMilli === 0) {
      throw new BadRequestException('quantity must be greater than 0');
    }

    const supply = await this.prisma.$transaction(async (tx) => {
      const current = await lockSupplies(tx, [id]);
      const row = current.get(id);
      if (!row) throw new NotFoundException('Supply not found');
      if (!row.isActive) throw new ConflictException('The supply is inactive');

      const stockMilli = toMilli(row.stock);
      const changeMilli = dto.type === MovementType.COUNT ? quantityMilli - stockMilli : -quantityMilli;
      if (stockMilli + changeMilli < 0) {
        throw new ConflictException(
          `Only ${fromMilli(stockMilli)} in stock; register a count if the real amount is different`,
        );
      }
      return applyMovement(tx, {
        supplyId: id,
        type: dto.type,
        changeMilli,
        stockMilli,
        note: dto.note,
        createdBy: actor.id,
      });
    });
    return this.publish(supply);
  }

  private publish<T extends { stock: Prisma.Decimal; minStock: Prisma.Decimal }>(supply: T) {
    const result = { ...supply, isLow: isLow(supply) };
    this.realtime.supplyUpdated(result);
    return result;
  }
}

export function isLow(supply: { stock: { toString(): string }; minStock: { toString(): string } }): boolean {
  const min = toMilli(supply.minStock);
  return min > 0 && toMilli(supply.stock) <= min;
}

/**
 * SELECT ... FOR UPDATE in id order: two purchases touching the same supplies always lock
 * them in the same order, so they wait for each other instead of deadlocking.
 */
export async function lockSupplies(tx: Tx, ids: number[]) {
  const sorted = [...new Set(ids)].sort((a, b) => a - b);
  const rows = await tx.$queryRaw<{ id: number; stock: string; isActive: number | boolean }[]>`
    SELECT id, stock, is_active AS isActive FROM supplies
    WHERE id IN (${Prisma.join(sorted)}) ORDER BY id FOR UPDATE`;
  return new Map(
    rows.map((row) => [Number(row.id), { stock: String(row.stock), isActive: Boolean(Number(row.isActive)) }]),
  );
}

export interface MovementInput {
  supplyId: number;
  type: MovementType;
  changeMilli: number;
  stockMilli: number;
  note?: string;
  expenseId?: number;
  createdBy: number;
}

/** Writes the new stock and its movement row; callers hold the supply's row lock. */
export async function applyMovement(tx: Tx, input: MovementInput) {
  const stockAfter = fromMilli(input.stockMilli + input.changeMilli);
  await tx.supplyMovement.create({
    data: {
      supplyId: input.supplyId,
      type: input.type,
      quantity: fromMilli(input.changeMilli),
      stockAfter,
      expenseId: input.expenseId ?? null,
      note: input.note ?? null,
      createdBy: input.createdBy,
    },
  });
  return tx.supply.update({ where: { id: input.supplyId }, data: { stock: stockAfter } });
}
