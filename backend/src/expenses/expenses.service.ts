// backend/src/expenses/expenses.service.ts
import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpenseCategory, MovementType, Prisma } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { businessDayRange } from '../common/utils/business-day';
import { fromDateColumn, toDateColumn } from '../common/utils/date-column';
import { fromCents, toCents } from '../common/utils/money';
import { fromMilli, toMilli } from '../common/utils/quantity';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { applyMovement, lockSupplies } from '../supplies/supplies.service';
import { CreateExpenseDto } from './dto/expense.dto';

const EXPENSE_INCLUDE = {
  creator: { select: { fullName: true } },
  items: { include: { supply: { select: { name: true, unit: true } } }, orderBy: { id: 'asc' } },
} as const;

type ExpenseRow = Prisma.ExpenseGetPayload<{ include: typeof EXPENSE_INCLUDE }>;

@Injectable()
export class ExpensesService {
  private readonly utcOffsetMinutes: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    config: ConfigService,
  ) {
    this.utcOffsetMinutes = Number(config.get('BUSINESS_UTC_OFFSET_MINUTES') ?? -300);
  }

  /** The day's expenses, newest first; voided ones stay visible (struck through) but do not add up. */
  async list(date?: string) {
    const day = businessDayRange(date, this.utcOffsetMinutes).date;
    const rows = await this.prisma.expense.findMany({
      where: { businessDate: toDateColumn(day) },
      include: EXPENSE_INCLUDE,
      orderBy: { id: 'desc' },
    });
    const valid = rows.filter((row) => !row.isVoid);
    const sum = (list: ExpenseRow[]) => fromCents(list.reduce((total, row) => total + toCents(row.amount), 0));
    return {
      date: day,
      total: sum(valid),
      cashTotal: sum(valid.filter((row) => row.paidWith === 'CASH')),
      expenses: rows.map(toResponse),
    };
  }

  /**
   * A supply purchase (items present) is always category INSUMOS and its amount is the sum of the
   * lines; the stock of each supply goes up in the same transaction, so both always agree.
   */
  async create(dto: CreateExpenseDto, actor: AuthenticatedUser) {
    const today = businessDayRange(undefined, this.utcOffsetMinutes).date;
    const day = businessDayRange(dto.businessDate, this.utcOffsetMinutes).date;
    if (day > today) throw new BadRequestException('An expense cannot be recorded for a future day');

    const items = dto.items ?? [];
    let amountCents: number;
    if (items.length > 0) {
      if (dto.category !== ExpenseCategory.INSUMOS) {
        throw new BadRequestException('A purchase with supplies must use the INSUMOS category');
      }
      if (new Set(items.map((item) => item.supplyId)).size !== items.length) {
        throw new BadRequestException('Each supply can appear only once per purchase');
      }
      amountCents = items.reduce((total, item) => total + toCents(item.cost), 0);
      if (amountCents === 0) throw new BadRequestException('The purchase total must be greater than 0');
      if (dto.amount !== undefined && toCents(dto.amount) !== amountCents) {
        throw new BadRequestException(`amount must equal the sum of the items (S/ ${fromCents(amountCents)})`);
      }
    } else {
      if (dto.amount === undefined) throw new BadRequestException('amount is required');
      amountCents = toCents(dto.amount);
    }

    const { expense, supplies } = await this.prisma.$transaction(async (tx) => {
      const locked = items.length ? await lockSupplies(tx, items.map((item) => item.supplyId)) : new Map();
      for (const item of items) {
        const supply = locked.get(item.supplyId);
        if (!supply) throw new BadRequestException(`Supply ${item.supplyId} does not exist`);
        if (!supply.isActive) throw new BadRequestException(`Supply ${item.supplyId} is inactive`);
      }

      const created = await tx.expense.create({
        data: {
          businessDate: toDateColumn(day),
          category: dto.category,
          description: dto.description,
          amount: fromCents(amountCents),
          paidWith: dto.paidWith,
          createdBy: actor.id,
          items: {
            create: items.map((item) => ({
              supplyId: item.supplyId,
              quantity: fromMilli(toMilli(item.quantity)),
              cost: fromCents(toCents(item.cost)),
            })),
          },
        },
      });

      const updated = [];
      for (const item of items) {
        updated.push(
          await applyMovement(tx, {
            supplyId: item.supplyId,
            type: MovementType.PURCHASE,
            changeMilli: toMilli(item.quantity),
            stockMilli: toMilli(locked.get(item.supplyId)!.stock),
            expenseId: created.id,
            createdBy: actor.id,
          }),
        );
      }
      return { expense: created, supplies: updated };
    });

    supplies.forEach((supply) => this.realtime.supplyUpdated(supply));
    return this.findOne(expense.id);
  }

  /**
   * No DELETE: a wrong expense is voided with a reason. A voided purchase takes its stock back out;
   * if part of it was already used or wasted, the kitchen must count first (stock never goes negative).
   */
  async void(id: number, reason: string, actor: AuthenticatedUser) {
    const supplies = await this.prisma.$transaction(async (tx) => {
      const lockedExpense = await tx.$queryRaw<{ id: number }[]>`
        SELECT id FROM expenses WHERE id = ${id} FOR UPDATE`;
      if (lockedExpense.length === 0) throw new NotFoundException('Expense not found');

      const expense = await tx.expense.findUniqueOrThrow({
        where: { id },
        include: { items: { include: { supply: { select: { name: true } } } } },
      });
      if (expense.isVoid) throw new ConflictException('The expense is already void');

      const locked = expense.items.length
        ? await lockSupplies(tx, expense.items.map((item) => item.supplyId))
        : new Map<number, { stock: string }>();
      const updated = [];
      for (const item of expense.items) {
        const stockMilli = toMilli(locked.get(item.supplyId)!.stock);
        const quantityMilli = toMilli(item.quantity);
        if (stockMilli < quantityMilli) {
          throw new ConflictException(
            `Cannot void: ${item.supply.name} has ${fromMilli(stockMilli)} left of the ` +
              `${fromMilli(quantityMilli)} bought; register a count first`,
          );
        }
        updated.push(
          await applyMovement(tx, {
            supplyId: item.supplyId,
            type: MovementType.VOID,
            changeMilli: -quantityMilli,
            stockMilli,
            expenseId: id,
            note: reason,
            createdBy: actor.id,
          }),
        );
      }
      await tx.expense.update({ where: { id }, data: { isVoid: true, voidReason: reason } });
      return updated;
    });

    supplies.forEach((supply) => this.realtime.supplyUpdated(supply));
    return this.findOne(id);
  }

  async findOne(id: number) {
    const row = await this.prisma.expense.findUnique({ where: { id }, include: EXPENSE_INCLUDE });
    if (!row) throw new NotFoundException('Expense not found');
    return toResponse(row);
  }
}

function toResponse({ creator, items, businessDate, ...row }: ExpenseRow) {
  return {
    ...row,
    businessDate: fromDateColumn(businessDate),
    createdBy: creator.fullName,
    items: items.map(({ supply, ...item }) => ({ ...item, supplyName: supply.name, unit: supply.unit })),
  };
}
