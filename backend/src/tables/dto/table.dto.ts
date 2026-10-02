// backend/src/tables/dto/table.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { IsBoolean, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

export class CreateTableDto {
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(20)
  label!: string;
}

export class UpdateTableDto extends PartialType(CreateTableDto) {
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
