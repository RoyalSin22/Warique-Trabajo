// backend/src/reports/reports.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { Roles } from '../auth/decorators/roles.decorator';
import { DailyReportQueryDto } from './dto/daily-report-query.dto';
import { SummaryQueryDto } from './dto/summary-query.dto';
import { BackupStatusService } from './backup-status.service';
import { ReportsService } from './reports.service';

@Roles(Role.OWNER)
@Controller('reports')
export class ReportsController {
  constructor(
    private readonly reportsService: ReportsService,
    private readonly backupStatusService: BackupStatusService,
  ) {}

  @Get('daily')
  daily(@Query() query: DailyReportQueryDto) {
    return this.reportsService.daily(query.date);
  }

  @Get('payments')
  payments(@Query() query: DailyReportQueryDto) {
    return this.reportsService.payments(query.date);
  }

  @Get('summary')
  summary(@Query() query: SummaryQueryDto) {
    return this.reportsService.summary(query.from, query.to);
  }

  @Get('backup-status')
  backupStatus() {
    return this.backupStatusService.read();
  }
}
