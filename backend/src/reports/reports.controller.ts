// backend/src/reports/reports.controller.ts
import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query } from '@nestjs/common';
import { Role } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { ExportLinkDto } from './dto/export.dto';
import { ExportService } from './export.service';
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
    private readonly exportService: ExportService,
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

  /** Step 1 (app, with the session): a signed link valid for 2 minutes. */
  @Post('export-link')
  @HttpCode(HttpStatus.OK)
  exportLink(@Body() dto: ExportLinkDto, @CurrentUser() user: AuthenticatedUser) {
    return this.exportService.createLink(dto.kind, dto.from, dto.to, user);
  }
}
