// backend/src/common/utils/business-day.ts
import { BadRequestException } from '@nestjs/common';

const DAY_MS = 24 * 60 * 60 * 1000;

export interface BusinessDayRange {
  date: string; // YYYY-MM-DD in business local time
  start: Date; // inclusive, UTC
  end: Date; // exclusive, UTC
}

/**
 * Converts a local business day (Peru = UTC-5, no DST) into a UTC range.
 * Timestamps are stored in UTC, so "today" must be translated before querying.
 */
export function businessDayRange(
  date: string | undefined,
  utcOffsetMinutes: number,
  now: Date = new Date(),
): BusinessDayRange {
  const offsetMs = utcOffsetMinutes * 60 * 1000;
  const day = date ?? new Date(now.getTime() + offsetMs).toISOString().slice(0, 10);

  const [year, month, dayOfMonth] = day.split('-').map(Number);
  const localMidnightAsUtc = Date.UTC(year, month - 1, dayOfMonth);
  const roundTrip = new Date(localMidnightAsUtc).toISOString().slice(0, 10);
  if (Number.isNaN(localMidnightAsUtc) || roundTrip !== day) {
    throw new BadRequestException(`Invalid date: ${day}`);
  }

  const start = new Date(localMidnightAsUtc - offsetMs);
  return { date: day, start, end: new Date(start.getTime() + DAY_MS) };
}
