// backend/src/auth/auth.controller.ts
import { Body, Controller, Get, HttpCode, HttpStatus, Patch, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ChangeOwnPasswordDto } from '../users/dto/user.dto';
import { AuthService, LoginResult } from './auth.service';
import { CurrentUser } from './decorators/current-user.decorator';
import { Public } from './decorators/public.decorator';
import { LoginDto } from './dto/login.dto';
import { AuthenticatedUser } from './interfaces/authenticated-user.interface';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Throttle({ default: { limit: 5, ttl: 60_000 } }) // brute-force protection
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto): Promise<LoginResult> {
    return this.authService.login(dto);
  }

  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser): AuthenticatedUser {
    return user;
  }

  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  /** Returns a new token: the old one (and every other session) stops working. */
  @Patch('password')
  @HttpCode(HttpStatus.OK)
  changeOwnPassword(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: ChangeOwnPasswordDto,
  ): Promise<LoginResult> {
    return this.authService.changeOwnPassword(user.id, dto);
  }
}
