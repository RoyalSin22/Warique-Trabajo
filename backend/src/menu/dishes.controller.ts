// backend/src/menu/dishes.controller.ts
import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { canSeeInactive } from '../common/utils/visibility';
import { DishesService } from './dishes.service';
import { CreateDishDto, ListDishesQueryDto, SetAvailabilityDto, UpdateDishDto } from './dto/dish.dto';

@Controller('dishes')
export class DishesController {
  constructor(private readonly dishesService: DishesService) {}

  @Get()
  findAll(@Query() query: ListDishesQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.dishesService.findAll({
      categoryId: query.categoryId,
      available: query.available,
      includeInactive: canSeeInactive(user, query.includeInactive),
    });
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.dishesService.findOne(id);
  }

  @Roles(Role.OWNER)
  @Post()
  create(@Body() dto: CreateDishDto) {
    return this.dishesService.create(dto);
  }

  @Roles(Role.OWNER, Role.KITCHEN)
  @Post('availability/reset')
  @HttpCode(HttpStatus.OK)
  resetAvailability() {
    return this.dishesService.resetAvailability();
  }

  @Roles(Role.OWNER)
  @Patch(':id')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateDishDto) {
    return this.dishesService.update(id, dto);
  }

  @Roles(Role.OWNER, Role.KITCHEN)
  @Patch(':id/availability')
  setAvailability(@Param('id', ParseIntPipe) id: number, @Body() dto: SetAvailabilityDto) {
    return this.dishesService.setAvailability(id, dto.isAvailable);
  }
}
