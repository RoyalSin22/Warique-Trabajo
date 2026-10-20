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
import {
  AddOrderItemsDto,
  CancelOrderItemDto,
  CreateOrderDto,
  ListOrdersQueryDto,
  UpdateOrderStatusDto,
} from './dto/order.dto';
import { CreatePaymentDto, VoidPaymentDto } from './dto/payment.dto';
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
  async findOne(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: AuthenticatedUser) {
    const order = await this.ordersService.findOne(id);
    if (user.role !== Role.KITCHEN) return order;
    // The kitchen cooks; payment details are not its business (same as the realtime feed)
    const { payments: _payments, ...forKitchen } = order;
    return forKitchen;
  }

  @Roles(Role.WAITER, Role.OWNER)
  @UseInterceptors(IdempotencyInterceptor) // a retried "Enviar a cocina" never creates two orders
  @Post()
  create(@Body() dto: CreateOrderDto, @CurrentUser() user: AuthenticatedUser) {
    return this.ordersService.create(dto, user);
  }

  /** More dishes for an order the kitchen has not finished (PENDING or IN_PREPARATION). */
  @Roles(Role.WAITER, Role.OWNER)
  @UseInterceptors(IdempotencyInterceptor)
  @Post(':id/items')
  addItems(@Param('id', ParseIntPipe) id: number, @Body() dto: AddOrderItemsDto) {
    return this.ordersService.addItems(id, dto);
  }

  /** PENDING: waiter or owner. Once the kitchen started: owner only (checked in the service). */
  @Roles(Role.WAITER, Role.OWNER)
  @UseInterceptors(IdempotencyInterceptor) // a retried "quitar 1 de 3" never removes two
  @Patch(':id/items/:itemId/cancel')
  cancelItem(
    @Param('id', ParseIntPipe) id: number,
    @Param('itemId', ParseIntPipe) itemId: number,
    @Body() dto: CancelOrderItemDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.ordersService.cancelItem(id, itemId, dto, user);
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

  /** A payment registered by mistake: only the owner can undo it, with a reason. */
  @Roles(Role.OWNER)
  @Patch(':id/payments/:paymentId/void')
  voidPayment(
    @Param('id', ParseIntPipe) id: number,
    @Param('paymentId', ParseIntPipe) paymentId: number,
    @Body() dto: VoidPaymentDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.paymentsService.void(id, paymentId, dto.reason, user);
  }
}
