// backend/src/reports/reports.module.ts
import { Module } from '@nestjs/common';
import { ReportsController } from './reports.controller';
import { BackupStatusService } from './backup-status.service';
import { ExportController } from './export.controller';
import { ExportService } from './export.service';
import { ReportsService } from './reports.service';

@Module({
  controllers: [ReportsController, ExportController],
  providers: [ReportsService, BackupStatusService, ExportService],
})
export class ReportsModule {}
