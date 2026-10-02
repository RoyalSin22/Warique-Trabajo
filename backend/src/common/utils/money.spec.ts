// backend/src/common/utils/money.spec.ts
import { fromCents, toCents } from './money';

describe('money utils', () => {
  it('converts decimal strings and numbers to cents', () => {
    expect(toCents('18.50')).toBe(1850);
    expect(toCents(0.1 + 0.2)).toBe(30);
    expect(toCents({ toString: () => '3.00' })).toBe(300);
  });

  it('treats null/undefined as zero', () => {
    expect(toCents(null)).toBe(0);
    expect(toCents(undefined)).toBe(0);
  });

  it('formats cents with two decimals', () => {
    expect(fromCents(4000)).toBe('40.00');
    expect(fromCents(5)).toBe('0.05');
  });

  it('rejects non-numeric input', () => {
    expect(() => toCents('abc')).toThrow();
  });
});
