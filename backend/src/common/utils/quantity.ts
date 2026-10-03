// backend/src/common/utils/quantity.ts
// Stock quantities (DECIMAL(12,3)) are added and subtracted in integer thousandths, like money in cents.

type QuantityInput = string | number | { toString(): string } | null | undefined;

export function toMilli(value: QuantityInput): number {
  if (value === null || value === undefined) return 0;
  const parsed = Number(value.toString());
  if (!Number.isFinite(parsed)) throw new Error(`Invalid quantity: ${String(value)}`);
  return Math.round(parsed * 1000);
}

/** Fixed 3-decimal string, the format Prisma accepts for DECIMAL(12,3) columns. */
export function fromMilli(milli: number): string {
  return (milli / 1000).toFixed(3);
}
