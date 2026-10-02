// backend/src/users/dto/user.dto.ts
import { Role } from '@prisma/client';
import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Trim } from '../../common/decorators/transform.decorators';

// bcrypt only uses the first 72 bytes, so longer passwords are rejected explicitly
const PASSWORD_MIN = 8;
const PASSWORD_MAX = 72;

export class CreateUserDto {
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  fullName!: string;

  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  @IsString()
  @Matches(/^[a-z0-9._-]{3,50}$/, {
    message: 'username must be 3-50 characters: lowercase letters, numbers, ".", "_" or "-"',
  })
  username!: string;

  @IsString()
  @MinLength(PASSWORD_MIN)
  @MaxLength(PASSWORD_MAX)
  password!: string;

  @IsEnum(Role)
  role!: Role;
}

export class UpdateUserDto {
  @IsOptional()
  @Trim()
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  fullName?: string;

  @IsOptional()
  @IsEnum(Role)
  role?: Role;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class ResetPasswordDto {
  @IsString()
  @MinLength(PASSWORD_MIN)
  @MaxLength(PASSWORD_MAX)
  password!: string;
}

export class ChangeOwnPasswordDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(PASSWORD_MAX)
  currentPassword!: string;

  @IsString()
  @MinLength(PASSWORD_MIN)
  @MaxLength(PASSWORD_MAX)
  newPassword!: string;
}
