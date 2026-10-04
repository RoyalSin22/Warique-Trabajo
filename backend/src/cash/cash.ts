// backend/src/cash/cash.ts
import { fromCents } from '../common/utils/money';

/**
 * Expected cash in the drawer = change fund + cash collected - expenses paid in cash.
 * Collected is the payment amount applied to orders (the change handed back never stayed).
 */
export function cashBalance(input: { openingCents: number; cashSalesCents: number; cashExpensesCents: number }) {
  const expectedCents = input.openingCents + input.cashSalesCents - input.cashExpensesCents;
  return {
    openingAmount: fromCents(input.openingCents),
    cashSales: fromCents(input.cashSalesCents),
    cashExpenses: fromCents(input.cashExpensesCents),
    expected: fromCents(expectedCents),
    expectedCents,
  };
}
