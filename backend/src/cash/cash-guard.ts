// backend/src/cash/cash-guard.ts
import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { toDateColumn } from '../common/utils/date-column';

/**
 * Cash movements (cash payments, cash expenses and their voids) are refused on a day whose cash
 * count is closed: the counted snapshot would silently stop matching. The owner reopens it first.
 * Days without a cash session (the drawer was never opened) are not restricted.
 */
export async function assertCashDayOpen(
  client: Pick<Prisma.TransactionClient, 'cashSession'>,
  businessDate: string,
): Promise<void> {
  const session = await client.cashSession.findUnique({
    where: { businessDate: toDateColumn(businessDate) },
    select: { closedAt: true },
  });
  if (session?.closedAt) {
    throw new ConflictException('The cash count for this day is closed: reopen it to register cash movements');
  }
}
