// backend/src/supplies/dto/supply.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import {
  IsBoolean,
  IsEnum,
  IsIn,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { MovementType, SupplyUnit } from '@prisma/client';
import { Trim } from '../../common/decorators/transform.decorators';

/** Up to 3 decimals: grams of a kilogram, millilitres of a litre. */
export const QUANTITY = { maxDecimalPlaces: 3, allowNaN: false, allowInfinity: false } as const;
export const MAX_QUANTITY = 999_999;

export class CreateSupplyDto {
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(60)
  name!: string;

  @IsEnum(SupplyUnit)
  unit!: SupplyUnit;

  /** "Stock bajo" threshold. Stock itself starts at 0 and only changes through movements. */
  @IsOptional()
  @IsNumber(QUANTITY)
  @Min(0)
  @Max(MAX_QUANTITY)
  minStock?: number;
}

export class UpdateSupplyDto extends PartialType(CreateSupplyDto) {
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

/** Movements anyone in the kitchen may register. Purchases come from expenses only. */
export const MANUAL_MOVEMENTS = [MovementType.COUNT, MovementType.WASTE, MovementType.USE] as const;
export type ManualMovement = (typeof MANUAL_MOVEMENTS)[number];

export class CreateMovementDto {
  @IsIn(MANUAL_MOVEMENTS)
  type!: ManualMovement;

  /** COUNT: the stock actually counted (absolute). WASTE/USE: how much went out. */
  @IsNumber(QUANTITY)
  @Min(0)
  @Max(MAX_QUANTITY)
  quantity!: number;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(150)
  note?: string;
}
