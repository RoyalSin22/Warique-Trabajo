// backend/src/common/dto/include-inactive-query.dto.ts
import { IsBoolean, IsOptional } from 'class-validator';
import { ToBoolean } from '../decorators/transform.decorators';

export class IncludeInactiveQueryDto {
  @IsOptional()
  @ToBoolean()
  @IsBoolean()
  includeInactive?: boolean;
}
