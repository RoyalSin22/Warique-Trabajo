// backend/src/menu/dto/dish.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { ToBoolean, Trim } from '../../common/decorators/transform.decorators';
import { IncludeInactiveQueryDto } from '../../common/dto/include-inactive-query.dto';

export class CreateDishDto {
  @IsInt()
  @Min(1)
  categoryId!: number;

  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(255)
  description?: string;

  /** At least S/ 0.01: an order with total 0 could never be paid and would stay "por cobrar". */
  @IsNumber({ maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false })
  @Min(0.01, { message: 'price must be greater than 0' })
  @Max(99999.99)
  price!: number;
}

export class UpdateDishDto extends PartialType(CreateDishDto) {
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class SetAvailabilityDto {
  @IsBoolean()
  isAvailable!: boolean;
}

export class ListDishesQueryDto extends IncludeInactiveQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  categoryId?: number;

  @IsOptional()
  @ToBoolean()
  @IsBoolean()
  available?: boolean;
}
