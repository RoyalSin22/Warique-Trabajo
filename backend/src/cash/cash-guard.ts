// backend/src/cash/cash-guard.ts
import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

/**
 * Cash movements (cash payments, cash expenses and their voids) are refused on a day whose cash
 * count is closed: the counted snapshot would silently stop matching. The owner reopens it first.
 * Days without a cash session (the drawer was never opened) are not restricted.
 *
 * Must run inside the transaction that writes the movement: the shared lock makes a concurrent
 * closing (which locks the same row FOR UPDATE) wait until this movement is committed, so the
 * closing snapshot always includes it.
 */
export async function assertCashDayOpen(
  tx: Pick<Prisma.TransactionClient, '$queryRaw'>,
  businessDate: string,
): Promise<void> {
  const rows = await tx.$queryRaw<{ closed_at: Date | null }[]>`
    SELECT closed_at FROM cash_sessions WHERE business_date = ${businessDate} LOCK IN SHARE MODE`;
  if (rows[0]?.closed_at) {
    throw new ConflictException('The cash count for this day is closed: reopen it to register cash movements');
  }
}
