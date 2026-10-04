import { fromMilli, toMilli } from './quantity';

describe('quantity helpers', () => {
  it('adds kilograms without floating-point drift', () => {
    expect(fromMilli(toMilli('0.1') + toMilli(0.2))).toBe('0.300');
  });

  it('keeps the sign for outgoing movements', () => {
    expect(fromMilli(-toMilli('1.5'))).toBe('-1.500');
  });

  it('treats a missing value as zero', () => {
    expect(toMilli(null)).toBe(0);
  });
});
