// backend/src/common/utils/business-day.spec.ts
import { BadRequestException } from '@nestjs/common';
import { businessDayRange } from './business-day';

describe('businessDayRange (Lima, UTC-5)', () => {
  const LIMA = -300;

  it('maps a local day to its UTC range', () => {
    const range = businessDayRange('2026-10-02', LIMA);
    expect(range.start.toISOString()).toBe('2026-10-02T05:00:00.000Z');
    expect(range.end.toISOString()).toBe('2026-10-03T05:00:00.000Z');
  });

  it('uses the local date for "today", not the UTC date', () => {
    // 03:00 UTC on Oct 3 is still 22:00 on Oct 2 in Lima
    const range = businessDayRange(undefined, LIMA, new Date('2026-10-03T03:00:00Z'));
    expect(range.date).toBe('2026-10-02');
  });

  it('rejects impossible dates', () => {
    expect(() => businessDayRange('2026-02-30', LIMA)).toThrow(BadRequestException);
  });
});
