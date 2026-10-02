// backend/src/reports/dto/daily-report-query.dto.ts
import { IsOptional, Matches } from 'class-validator';

export class DailyReportQueryDto {
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'date must be YYYY-MM-DD' })
  date?: string;
}
