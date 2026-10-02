// backend/src/auth/decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthenticatedUser } from '../interfaces/authenticated-user.interface';

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthenticatedUser =>
    ctx.switchToHttp().getRequest().user,
);
