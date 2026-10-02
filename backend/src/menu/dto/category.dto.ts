// backend/src/menu/dto/category.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { IsBoolean, IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

export class CreateCategoryDto {
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(60)
  name!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(65535)
  sortOrder?: number;
}

export class UpdateCategoryDto extends PartialType(CreateCategoryDto) {
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
