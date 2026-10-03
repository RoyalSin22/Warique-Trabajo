// backend/src/expenses/dto/expense.dto.ts
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { ExpenseCategory, PaidWith } from '@prisma/client';
import { Trim } from '../../common/decorators/transform.decorators';
import { MAX_QUANTITY, QUANTITY } from '../../supplies/dto/supply.dto';

const MONEY = { maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false } as const;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export class ExpenseItemDto {
  @IsInt()
  @Min(1)
  supplyId!: number;

  @IsNumber(QUANTITY)
  @Min(0.001)
  @Max(MAX_QUANTITY)
  quantity!: number;

  /** What was paid for this line (not the unit price). */
  @IsNumber(MONEY)
  @Min(0)
  @Max(99999.99)
  cost!: number;
}

export class CreateExpenseDto {
  /** Business day the expense belongs to; defaults to today. Never in the future. */
  @IsOptional()
  @Matches(DATE, { message: 'businessDate must be YYYY-MM-DD' })
  businessDate?: string;

  @IsEnum(ExpenseCategory)
  category!: ExpenseCategory;

  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(150)
  description!: string;

  /** Required without items; with items it is their sum (sending a different value is an error). */
  @IsOptional()
  @IsNumber(MONEY)
  @Min(0.01)
  @Max(99999.99)
  amount?: number;

  /** CASH comes out of the drawer and lowers the expected cash at closing. */
  @IsEnum(PaidWith)
  paidWith!: PaidWith;

  /** Supply purchase: each line adds stock. */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(30)
  @ValidateNested({ each: true })
  @Type(() => ExpenseItemDto)
  items?: ExpenseItemDto[];
}

export class VoidExpenseDto {
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(150)
  reason!: string;
}

export class ListExpensesQueryDto {
  @IsOptional()
  @Matches(DATE, { message: 'date must be YYYY-MM-DD' })
  date?: string;
}
