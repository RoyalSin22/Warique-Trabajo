// backend/src/reports/export.controller.ts
import { Controller, Get, Header, HttpStatus, Param, Res } from '@nestjs/common';
import { Response } from 'express';
import { Public } from '../auth/decorators/public.decorator';
import { ExportService } from './export.service';

/**
 * Step 2 of an export (step 1 is POST /reports/export-link): the browser downloads the file with
 * no session header, so the signed link itself is the credential. Kept out of ReportsController,
 * whose class-wide OWNER role would otherwise apply to this public route.
 */
@Public()
@Controller('reports/export')
export class ExportController {
  constructor(private readonly exportService: ExportService) {}

  @Get(':token')
  @Header('Cache-Control', 'no-store')
  async download(@Param('token') token: string, @Res() response: Response) {
    const file = await this.exportService.download(token);
    response.status(HttpStatus.OK).type('text/csv; charset=utf-8').attachment(file.fileName).send(file.content);
  }
}
