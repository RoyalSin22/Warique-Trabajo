// backend/src/cash/cash.service.ts
import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaidWith, PaymentMethod, Prisma } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { businessDayRange } from '../common/utils/business-day';
import { fromDateColumn, toDateColumn } from '../common/utils/date-column';
import { fromCents, toCents } from '../common/utils/money';
import { PrismaService } from '../prisma/prisma.service';
import { cashBalance } from './cash';

const SESSION_INCLUDE = {
  opener: { select: { fullName: true } },
  closer: { select: { fullName: true } },
} as const;

type SessionRow = Prisma.CashSessionGetPayload<{ include: typeof SESSION_INCLUDE }>;

/** Daily cash count (arqueo): open with the change fund, close with what was counted. */
@Injectable()
export class CashService {
  private readonly utcOffsetMinutes: number;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    this.utcOffsetMinutes = Number(config.get('BUSINESS_UTC_OFFSET_MINUTES') ?? -300);
  }

  /** `live` is recomputed on every call; `session` keeps the snapshot taken at closing. */
  async day(date?: string) {
    const range = this.range(date);
    const session = await this.prisma.cashSession.findUnique({
      where: { businessDate: toDateColumn(range.date) },
      include: SESSION_INCLUDE,
    });
    const { expectedCents: _omit, ...live } = await this.balance(range, toCents(session?.openingAmount));
    return { date: range.date, session: session ? toResponse(session) : null, live };
  }

  /** Opening again before closing corrects the change fund (a typo should not need a new day). */
  async open(date: string | undefined, openingAmount: number, actor: AuthenticatedUser) {
    const range = this.range(date);
    const businessDate = toDateColumn(range.date);
    const existing = await this.prisma.cashSession.findUnique({ where: { businessDate } });
    if (existing?.closedAt) throw new ConflictException('The cash count for this day is already closed');

    const amount = fromCents(toCents(openingAmount));
    await this.prisma.cashSession.upsert({
      where: { businessDate },
      create: { businessDate, openingAmount: amount, openedBy: actor.id },
      update: { openingAmount: amount, openedBy: actor.id, openedAt: new Date() },
    });
    return this.day(range.date);
  }

  /**
   * Snapshots the expected amount and the difference (counted - expected; negative = missing).
   * Closing again is a recount: it replaces the previous snapshot.
   */
  async close(date: string | undefined, countedAmount: number, notes: string | undefined, actor: AuthenticatedUser) {
    const range = this.range(date);
    const businessDate = toDateColumn(range.date);
    const session = await this.prisma.cashSession.findUnique({ where: { businessDate } });
    if (!session) throw new ConflictException('Open the cash count with the change fund first');

    const { expectedCents } = await this.balance(range, toCents(session.openingAmount));
    const countedCents = toCents(countedAmount);
    await this.prisma.cashSession.update({
      where: { businessDate },
      data: {
        expectedAmount: fromCents(expectedCents),
        countedAmount: fromCents(countedCents),
        difference: fromCents(countedCents - expectedCents),
        notes: notes || null,
        closedBy: actor.id,
        closedAt: new Date(),
      },
    });
    return this.day(range.date);
  }

  private range(date?: string) {
    const range = businessDayRange(date, this.utcOffsetMinutes);
    const today = businessDayRange(undefined, this.utcOffsetMinutes).date;
    if (range.date > today) throw new BadRequestException('The cash count cannot be for a future day');
    return range;
  }

  private async balance(range: { date: string; start: Date; end: Date }, openingCents: number) {
    const [payments, expenses] = await Promise.all([
      this.prisma.payment.aggregate({
        where: { method: PaymentMethod.CASH, createdAt: { gte: range.start, lt: range.end } },
        _sum: { amount: true },
      }),
      this.prisma.expense.aggregate({
        where: { businessDate: toDateColumn(range.date), paidWith: PaidWith.CASH, isVoid: false },
        _sum: { amount: true },
      }),
    ]);
    return cashBalance({
      openingCents,
      cashSalesCents: toCents(payments._sum.amount),
      cashExpensesCents: toCents(expenses._sum.amount),
    });
  }
}

function toResponse({ opener, closer, businessDate, ...row }: SessionRow) {
  return {
    ...row,
    businessDate: fromDateColumn(businessDate),
    openedByName: opener.fullName,
    closedByName: closer?.fullName ?? null,
  };
}
