// backend/src/reports/export.service.ts
import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'crypto';
import { JwtService } from '@nestjs/jwt';
import { OrderStatus, Role } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { businessDayRange } from '../common/utils/business-day';
import { fromDateColumn, toDateColumn } from '../common/utils/date-column';
import { PrismaService } from '../prisma/prisma.service';
import { cashCsv, dailySalesCsv, expensesCsv, ExportKind, paymentsCsv } from './export';
import { dayRange } from './summary';

const MAX_EXPORT_DAYS = 366;
/** The link is opened right away by the app; a short life keeps a leaked URL useless. */
const LINK_TTL_SECONDS = 120;
const PURPOSE = 'export';

interface ExportClaims {
  sub: number;
  purpose: typeof PURPOSE;
  kind: ExportKind;
  from: string;
  to: string;
}

const FILE_NAMES: Record<ExportKind, string> = {
  ventas: 'ventas-diarias',
  pagos: 'pagos',
  gastos: 'gastos',
  arqueos: 'arqueos',
};

/**
 * CSV downloads for the accountant. The app asks for a signed, short-lived link and lets the
 * browser download it: the session token never travels in a URL, and the file opens in the
 * phone's or PC's own downloads like any other.
 */
@Injectable()
export class ExportService {
  private readonly utcOffsetMinutes: number;
  /**
   * Own key, derived from JWT_SECRET: a download link must never work as a session token (and a
   * session token never as a link). Same secret would let a leaked 2-minute link call the API
   * as the owner.
   */
  private readonly linkSecret: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    config: ConfigService,
  ) {
    this.utcOffsetMinutes = Number(config.get('BUSINESS_UTC_OFFSET_MINUTES') ?? -300);
    this.linkSecret = createHmac('sha256', config.getOrThrow<string>('JWT_SECRET'))
      .update('warique:export-link')
      .digest('base64');
  }

  async createLink(kind: ExportKind, from: string, to: string, actor: AuthenticatedUser) {
    this.days(from, to); // validate before signing
    const claims: ExportClaims = { sub: actor.id, purpose: PURPOSE, kind, from, to };
    const token = await this.jwt.signAsync(claims, { secret: this.linkSecret, expiresIn: LINK_TTL_SECONDS });
    return { url: `/api/reports/export/${token}`, fileName: fileName(kind, from, to), expiresInSeconds: LINK_TTL_SECONDS };
  }

  /** Verifies the link and that its owner is still an active OWNER (a fired owner's link dies too). */
  async download(token: string): Promise<{ fileName: string; content: string }> {
    let claims: ExportClaims;
    try {
      claims = await this.jwt.verifyAsync<ExportClaims>(token, { secret: this.linkSecret });
    } catch {
      throw new ForbiddenException('The download link expired. Request it again');
    }
    if (claims.purpose !== PURPOSE) throw new ForbiddenException('Invalid download link');
    const user = await this.prisma.user.findUnique({ where: { id: claims.sub }, select: { role: true, isActive: true } });
    if (!user?.isActive || user.role !== Role.OWNER) throw new ForbiddenException('Invalid download link');

    return { fileName: fileName(claims.kind, claims.from, claims.to), content: await this.build(claims.kind, claims.from, claims.to) };
  }

  async build(kind: ExportKind, from: string, to: string): Promise<string> {
    const days = this.days(from, to);
    const start = businessDayRange(from, this.utcOffsetMinutes).start;
    const end = businessDayRange(to, this.utcOffsetMinutes).end;
    const createdInRange = { createdAt: { gte: start, lt: end } };
    const businessDates = { businessDate: { gte: toDateColumn(from), lte: toDateColumn(to) } };

    switch (kind) {
      case 'ventas': {
        const [orders, payments, expenses] = await Promise.all([
          this.prisma.order.findMany({
            where: { ...createdInRange, status: { not: OrderStatus.CANCELLED } },
            select: { createdAt: true, total: true },
          }),
          this.prisma.payment.findMany({ where: createdInRange, select: { createdAt: true, method: true, amount: true } }),
          this.prisma.expense.groupBy({ by: ['businessDate'], where: { ...businessDates, isVoid: false }, _sum: { amount: true } }),
        ]);
        return dailySalesCsv({
          days,
          utcOffsetMinutes: this.utcOffsetMinutes,
          orders,
          payments,
          expenses: expenses.map((row) => ({ date: fromDateColumn(row.businessDate), amount: row._sum.amount })),
        });
      }
      case 'pagos': {
        const rows = await this.prisma.payment.findMany({
          where: createdInRange,
          include: {
            registeredUser: { select: { fullName: true } },
            order: { select: { orderType: true, customerName: true, table: { select: { label: true } } } },
          },
          orderBy: { createdAt: 'asc' },
        });
        return paymentsCsv(
          rows.map((row) => ({
            ...row,
            registeredBy: row.registeredUser.fullName,
            target:
              row.order.table?.label ??
              (row.order.customerName ? `Para llevar · ${row.order.customerName}` : 'Para llevar'),
          })),
          this.utcOffsetMinutes,
        );
      }
      case 'gastos': {
        const rows = await this.prisma.expense.findMany({
          where: businessDates,
          include: {
            creator: { select: { fullName: true } },
            items: { include: { supply: { select: { name: true, unit: true } } }, orderBy: { id: 'asc' } },
          },
          orderBy: [{ businessDate: 'asc' }, { id: 'asc' }],
        });
        return expensesCsv(
          rows.map((row) => ({
            ...row,
            businessDate: fromDateColumn(row.businessDate),
            createdBy: row.creator.fullName,
            items: row.items.map((item) => ({ ...item, supplyName: item.supply.name, unit: item.supply.unit })),
          })),
        );
      }
      case 'arqueos': {
        const rows = await this.prisma.cashSession.findMany({
          where: businessDates,
          include: { opener: { select: { fullName: true } }, closer: { select: { fullName: true } } },
          orderBy: { businessDate: 'asc' },
        });
        return cashCsv(
          rows.map((row) => ({
            ...row,
            businessDate: fromDateColumn(row.businessDate),
            openedBy: row.opener.fullName,
            closedBy: row.closer?.fullName ?? null,
          })),
          this.utcOffsetMinutes,
        );
      }
    }
  }

  private days(from: string, to: string): string[] {
    businessDayRange(from, this.utcOffsetMinutes); // rejects impossible dates (2026-02-30)
    businessDayRange(to, this.utcOffsetMinutes);
    const days = dayRange(from, to);
    if (days.length === 0) throw new BadRequestException('from must be on or before to');
    if (days.length > MAX_EXPORT_DAYS) throw new BadRequestException(`The range cannot exceed ${MAX_EXPORT_DAYS} days`);
    return days;
  }
}

function fileName(kind: ExportKind, from: string, to: string): string {
  return `warique-${FILE_NAMES[kind]}-${from}_a_${to}.csv`;
}
