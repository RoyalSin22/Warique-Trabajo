// backend/src/orders/orders.module.ts
import { Module } from '@nestjs/common';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';
import { PaymentsService } from './payments.service';

@Module({
  controllers: [OrdersController],
  providers: [OrdersService, PaymentsService],
})
export class OrdersModule {}
