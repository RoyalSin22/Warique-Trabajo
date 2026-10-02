// backend/src/tables/tables.controller.ts
import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IncludeInactiveQueryDto } from '../common/dto/include-inactive-query.dto';
import { canSeeInactive } from '../common/utils/visibility';
import { CreateTableDto, UpdateTableDto } from './dto/table.dto';
import { TablesService } from './tables.service';

@Controller('tables')
export class TablesController {
  constructor(private readonly tablesService: TablesService) {}

  @Get()
  findAll(@Query() query: IncludeInactiveQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.tablesService.findAll(canSeeInactive(user, query.includeInactive));
  }

  @Roles(Role.OWNER)
  @Post()
  create(@Body() dto: CreateTableDto) {
    return this.tablesService.create(dto);
  }

  @Roles(Role.OWNER)
  @Patch(':id')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateTableDto) {
    return this.tablesService.update(id, dto);
  }
}
