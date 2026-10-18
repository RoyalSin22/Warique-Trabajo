// backend/src/orders/active-payment.ts
/**
 * Where-clause for payments that count: a voided payment stays in the table for the audit trail,
 * but every total (order balance, reports, cash count, exports) must skip it.
 */
export const ACTIVE_PAYMENT = { voidedAt: null } as const;
