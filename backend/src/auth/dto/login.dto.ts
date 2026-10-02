// backend/src/auth/dto/login.dto.ts
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class LoginDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  username!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  password!: string;
}
