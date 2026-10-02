// backend/src/users/users.controller.ts
import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { IncludeInactiveQueryDto } from '../common/dto/include-inactive-query.dto';
import { CreateUserDto, ResetPasswordDto, UpdateUserDto } from './dto/user.dto';
import { UsersService } from './users.service';

@Roles(Role.OWNER)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  findAll(@Query() query: IncludeInactiveQueryDto) {
    return this.usersService.findAll(query.includeInactive === true);
  }

  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }

  @Patch(':id')
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
    @CurrentUser() actor: AuthenticatedUser,
  ) {
    return this.usersService.update(id, dto, actor);
  }

  @Patch(':id/password')
  resetPassword(@Param('id', ParseIntPipe) id: number, @Body() dto: ResetPasswordDto) {
    return this.usersService.resetPassword(id, dto.password);
  }
}
