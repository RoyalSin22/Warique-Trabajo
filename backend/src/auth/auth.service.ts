// backend/src/auth/auth.service.ts
import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { ChangeOwnPasswordDto } from '../users/dto/user.dto';
import { LoginDto } from './dto/login.dto';
import { AuthenticatedUser, JwtPayload } from './interfaces/authenticated-user.interface';
import { hashPassword, verifyPassword } from './password.util';

// Compared when the username does not exist, so response time does not reveal valid usernames
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 12);

export interface LoginResult {
  accessToken: string;
  user: AuthenticatedUser;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  async login(dto: LoginDto): Promise<LoginResult> {
    const user = await this.prisma.user.findUnique({ where: { username: dto.username } });
    const passwordMatches = await verifyPassword(dto.password, user?.passwordHash ?? DUMMY_HASH);

    if (!user || !user.isActive || !passwordMatches) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const payload: JwtPayload = { sub: user.id, username: user.username, role: user.role };
    return {
      accessToken: await this.jwt.signAsync(payload),
      user: { id: user.id, username: user.username, fullName: user.fullName, role: user.role },
    };
  }

  async changeOwnPassword(userId: number, dto: ChangeOwnPasswordDto): Promise<void> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { passwordHash: true },
    });
    if (!user || !(await verifyPassword(dto.currentPassword, user.passwordHash))) {
      throw new BadRequestException('Current password is incorrect');
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: await hashPassword(dto.newPassword) },
    });
  }
}
