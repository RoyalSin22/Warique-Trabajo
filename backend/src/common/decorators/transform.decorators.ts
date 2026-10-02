// backend/src/common/decorators/transform.decorators.ts
import { Transform } from 'class-transformer';

/** Trims string input before validation (" Ceviche " -> "Ceviche"). */
export const Trim = () =>
  Transform(({ value }) => (typeof value === 'string' ? value.trim() : value));

/** Converts query-string booleans ("true"/"false") into real booleans. */
export const ToBoolean = () =>
  Transform(({ value }) => {
    if (value === true || value === 'true') return true;
    if (value === false || value === 'false') return false;
    return value; // left as-is so @IsBoolean rejects invalid input
  });
