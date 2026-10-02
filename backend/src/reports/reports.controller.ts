// backend/src/reports/reports.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { Roles } from '../auth/decorators/roles.decorator';
import { DailyReportQueryDto } from './dto/daily-report-query.dto';
import { ReportsService } from './reports.service';

@Roles(Role.OWNER)
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('daily')
  daily(@Query() query: DailyReportQueryDto) {
    return this.reportsService.daily(query.date);
  }
}
