// backend/src/orders/active-item.ts
/** Order lines that count: a removed line stays for the audit trail but is in no total or report. */
export const ACTIVE_ITEM = { cancelledAt: null } as const;
