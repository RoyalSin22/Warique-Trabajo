// backend/src/cash/cash.controller.ts
import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { CashService } from './cash.service';
import { CashDayQueryDto, CloseCashDto, OpenCashDto } from './dto/cash.dto';

@Roles(Role.OWNER)
@Controller('cash')
export class CashController {
  constructor(private readonly cashService: CashService) {}

  @Get()
  day(@Query() query: CashDayQueryDto) {
    return this.cashService.day(query.date);
  }

  @Post('open')
  @HttpCode(HttpStatus.OK)
  open(@Body() dto: OpenCashDto, @CurrentUser() user: AuthenticatedUser) {
    return this.cashService.open(dto.date, dto.openingAmount, user);
  }

  @Post('close')
  @HttpCode(HttpStatus.OK)
  close(@Body() dto: CloseCashDto, @CurrentUser() user: AuthenticatedUser) {
    return this.cashService.close(dto.date, dto.countedAmount, dto.notes, user);
  }
}
