// backend/src/cash/dto/cash.dto.ts
import { IsNumber, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

const MONEY = { maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false } as const;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export class CashDayQueryDto {
  @IsOptional()
  @Matches(DATE, { message: 'date must be YYYY-MM-DD' })
  date?: string;
}

export class OpenCashDto extends CashDayQueryDto {
  /** Change fund put in the drawer before the first customer. */
  @IsNumber(MONEY)
  @Min(0)
  @Max(99999.99)
  openingAmount!: number;
}

export class CloseCashDto extends CashDayQueryDto {
  /** Cash physically counted in the drawer at closing. */
  @IsNumber(MONEY)
  @Min(0)
  @Max(999999.99)
  countedAmount!: number;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(255)
  notes?: string;
}
