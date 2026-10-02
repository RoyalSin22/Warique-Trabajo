// backend/src/auth/guards/jwt-auth.guard.ts
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { PrismaService } from '../../prisma/prisma.service';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { AuthenticatedUser, JwtPayload } from '../interfaces/authenticated-user.interface';

type AuthRequest = Request & { user?: AuthenticatedUser };

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<AuthRequest>();
    const token = this.extractBearerToken(request);
    if (!token) throw new UnauthorizedException('Missing token');

    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(token);
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }

    // PK lookup: deactivating a user or changing their role takes effect immediately
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, username: true, fullName: true, role: true, isActive: true },
    });
    if (!user || !user.isActive) throw new UnauthorizedException('User is not active');

    request.user = { id: user.id, username: user.username, fullName: user.fullName, role: user.role };
    return true;
  }

  private extractBearerToken(request: Request): string | undefined {
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    return type === 'Bearer' ? token : undefined;
  }
}
