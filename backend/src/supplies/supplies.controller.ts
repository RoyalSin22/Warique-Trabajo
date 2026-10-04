// backend/src/supplies/supplies.controller.ts
import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query, UseInterceptors } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IncludeInactiveQueryDto } from '../common/dto/include-inactive-query.dto';
import { IdempotencyInterceptor } from '../common/idempotency/idempotency.interceptor';
import { canSeeInactive } from '../common/utils/visibility';
import { CreateMovementDto, CreateSupplyDto, UpdateSupplyDto } from './dto/supply.dto';
import { SuppliesService } from './supplies.service';

@Roles(Role.OWNER, Role.KITCHEN)
@Controller('supplies')
export class SuppliesController {
  constructor(private readonly suppliesService: SuppliesService) {}

  @Get()
  findAll(@Query() query: IncludeInactiveQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.suppliesService.findAll(canSeeInactive(user, query.includeInactive));
  }

  @Get(':id/movements')
  movements(@Param('id', ParseIntPipe) id: number) {
    return this.suppliesService.movements(id);
  }

  @Roles(Role.OWNER)
  @Post()
  create(@Body() dto: CreateSupplyDto) {
    return this.suppliesService.create(dto);
  }

  @Roles(Role.OWNER)
  @Patch(':id')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateSupplyDto) {
    return this.suppliesService.update(id, dto);
  }

  /** Counts, waste and use. A retried "Guardar" must not subtract the waste twice. */
  @UseInterceptors(IdempotencyInterceptor)
  @Post(':id/movements')
  addMovement(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CreateMovementDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.suppliesService.addMovement(id, dto, user);
  }
}
