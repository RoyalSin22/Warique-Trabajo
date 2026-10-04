import { IsIn, Matches } from 'class-validator';
import { EXPORT_KINDS, ExportKind } from '../export';

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export class ExportLinkDto {
  @IsIn(EXPORT_KINDS)
  kind!: ExportKind;

  @Matches(DATE, { message: 'from must be YYYY-MM-DD' })
  from!: string;

  @Matches(DATE, { message: 'to must be YYYY-MM-DD' })
  to!: string;
}
