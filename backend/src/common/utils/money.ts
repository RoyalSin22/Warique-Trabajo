// backend/src/common/utils/money.ts
// All money arithmetic is done in integer cents to avoid floating-point errors (0.1 + 0.2 != 0.3).

type MoneyInput = string | number | { toString(): string } | null | undefined;

export function toCents(value: MoneyInput): number {
  if (value === null || value === undefined) return 0;
  const parsed = Number(value.toString());
  if (!Number.isFinite(parsed)) throw new Error(`Invalid money value: ${String(value)}`);
  return Math.round(parsed * 100);
}

/** Returns a fixed 2-decimal string, the format Prisma accepts for DECIMAL columns. */
export function fromCents(cents: number): string {
  return (cents / 100).toFixed(2);
}
