// backend/src/common/utils/date-column.ts
// MySQL DATE columns travel through Prisma as Date at UTC midnight; these keep that detail in one place.

export function toDateColumn(day: string): Date {
  return new Date(`${day}T00:00:00.000Z`);
}

export function fromDateColumn(value: Date): string {
  return value.toISOString().slice(0, 10);
}
