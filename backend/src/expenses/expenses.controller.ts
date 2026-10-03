// backend/src/expenses/expenses.controller.ts
import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query, UseInterceptors } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IdempotencyInterceptor } from '../common/idempotency/idempotency.interceptor';
import { CreateExpenseDto, ListExpensesQueryDto, VoidExpenseDto } from './dto/expense.dto';
import { ExpensesService } from './expenses.service';

/** Only the owner records and sees money going out. */
@Roles(Role.OWNER)
@Controller('expenses')
export class ExpensesController {
  constructor(private readonly expensesService: ExpensesService) {}

  @Get()
  list(@Query() query: ListExpensesQueryDto) {
    return this.expensesService.list(query.date);
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.expensesService.findOne(id);
  }

  /** A retried "Guardar" must not add the stock (or the expense) twice. */
  @UseInterceptors(IdempotencyInterceptor)
  @Post()
  create(@Body() dto: CreateExpenseDto, @CurrentUser() user: AuthenticatedUser) {
    return this.expensesService.create(dto, user);
  }

  @Patch(':id/void')
  void(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: VoidExpenseDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.expensesService.void(id, dto.reason, user);
  }
}
