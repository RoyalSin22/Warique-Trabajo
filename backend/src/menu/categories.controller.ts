// backend/src/menu/categories.controller.ts
import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IncludeInactiveQueryDto } from '../common/dto/include-inactive-query.dto';
import { canSeeInactive } from '../common/utils/visibility';
import { CategoriesService } from './categories.service';
import { CreateCategoryDto, UpdateCategoryDto } from './dto/category.dto';

@Controller('categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  @Get()
  findAll(@Query() query: IncludeInactiveQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.categoriesService.findAll(canSeeInactive(user, query.includeInactive));
  }

  @Roles(Role.OWNER)
  @Post()
  create(@Body() dto: CreateCategoryDto) {
    return this.categoriesService.create(dto);
  }

  @Roles(Role.OWNER)
  @Patch(':id')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateCategoryDto) {
    return this.categoriesService.update(id, dto);
  }
}
