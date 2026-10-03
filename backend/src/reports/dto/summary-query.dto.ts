import { Matches } from 'class-validator';

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export class SummaryQueryDto {
  /** First business day (YYYY-MM-DD, local time), inclusive. */
  @Matches(DATE, { message: 'from must be YYYY-MM-DD' })
  from!: string;

  /** Last business day (YYYY-MM-DD, local time), inclusive. */
  @Matches(DATE, { message: 'to must be YYYY-MM-DD' })
  to!: string;
}
