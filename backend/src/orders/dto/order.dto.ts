// backend/src/orders/dto/order.dto.ts
import { OrderStatus, OrderType, PaymentStatus } from '@prisma/client';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

export class CreateOrderItemDto {
  @IsInt()
  @Min(1)
  dishId!: number;

  @IsInt()
  @Min(1)
  @Max(99)
  quantity!: number;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(150)
  notes?: string;
}

export class CreateOrderDto {
  @IsEnum(OrderType)
  orderType!: OrderType;

  @IsOptional()
  @IsInt()
  @Min(1)
  tableId?: number;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(80)
  customerName?: string;

  @IsOptional()
  @Trim()
  @IsString()
  @MaxLength(255)
  notes?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => CreateOrderItemDto)
  items!: CreateOrderItemDto[];
}

export class UpdateOrderStatusDto {
  @IsEnum(OrderStatus)
  status!: OrderStatus;

  @IsOptional()
  @Trim()
  @IsString()
  @MinLength(3)
  @MaxLength(255)
  cancelReason?: string;
}

export class ListOrdersQueryDto {
  /** Comma-separated: ?status=PENDING,IN_PREPARATION */
  @IsOptional()
  @Transform(({ value }) =>
    typeof value === 'string'
      ? value.split(',').map((status) => status.trim()).filter(Boolean)
      : value,
  )
  @IsArray()
  @IsEnum(OrderStatus, { each: true })
  status?: OrderStatus[];

  @IsOptional()
  @IsEnum(PaymentStatus)
  paymentStatus?: PaymentStatus;

  /** Business day in local time (YYYY-MM-DD). Defaults to today. */
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'date must be YYYY-MM-DD' })
  date?: string;
}
