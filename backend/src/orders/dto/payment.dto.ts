// backend/src/orders/dto/payment.dto.ts
import { PaymentMethod } from '@prisma/client';
import { IsEnum, IsNumber, IsOptional, IsString, Matches, Max, Min } from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

const MONEY = { maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false } as const;

export class CreatePaymentDto {
  @IsEnum(PaymentMethod)
  method!: PaymentMethod;

  @IsNumber(MONEY)
  @Min(0.01)
  @Max(99999.99)
  amount!: number;

  /** CASH only: bill handed over by the customer (change is computed by the DB). */
  @IsOptional()
  @IsNumber(MONEY)
  @Min(0.01)
  @Max(99999.99)
  amountReceived?: number;

  /** YAPE/PLIN only: operation number shown in the customer's app. */
  @IsOptional()
  @Trim()
  @IsString()
  @Matches(/^[A-Za-z0-9-]{4,30}$/, { message: 'operationNumber must be 4-30 letters/digits' })
  operationNumber?: string;
}
