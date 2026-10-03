// backend/src/orders/orders.controller.ts
import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  UseInterceptors,
} from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IdempotencyInterceptor } from '../common/idempotency/idempotency.interceptor';
import { CreateOrderDto, ListOrdersQueryDto, UpdateOrderStatusDto } from './dto/order.dto';
import { CreatePaymentDto } from './dto/payment.dto';
import { OrdersService } from './orders.service';
import { PaymentsService } from './payments.service';

@Controller('orders')
export class OrdersController {
  constructor(
    private readonly ordersService: OrdersService,
    private readonly paymentsService: PaymentsService,
  ) {}

  @Get()
  findAll(@Query() query: ListOrdersQueryDto) {
    return this.ordersService.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.ordersService.findOne(id);
  }

  @Roles(Role.WAITER, Role.OWNER)
  @UseInterceptors(IdempotencyInterceptor) // a retried "Enviar a cocina" never creates two orders
  @Post()
  create(@Body() dto: CreateOrderDto, @CurrentUser() user: AuthenticatedUser) {
    return this.ordersService.create(dto, user);
  }

  /** Role rules per transition live in order-status.ts */
  @Patch(':id/status')
  updateStatus(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateOrderStatusDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.ordersService.updateStatus(id, dto, user);
  }

  @Roles(Role.WAITER, Role.OWNER)
  @UseInterceptors(IdempotencyInterceptor)
  @Post(':id/payments')
  registerPayment(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CreatePaymentDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.paymentsService.register(id, dto, user);
  }
}
