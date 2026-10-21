import {
  BadRequestException,
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { Request } from 'express';
import { from, lastValueFrom, Observable } from 'rxjs';
import { AuthenticatedUser } from '../../auth/interfaces/authenticated-user.interface';
import { IdempotencyStore } from './idempotency.store';

export const IDEMPOTENCY_HEADER = 'idempotency-key';
const KEY_PATTERN = /^[A-Za-z0-9-]{8,64}$/;

/**
 * Opt-in per handler with @UseInterceptors(IdempotencyInterceptor). Requests without the header
 * behave as before. The key is scoped to the user and the URL, so two waiters (or the same key on
 * another order) never collide.
 */
@Injectable()
export class IdempotencyInterceptor implements NestInterceptor {
  constructor(private readonly store: IdempotencyStore) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    const header = request.headers[IDEMPOTENCY_HEADER];
    if (header === undefined) return next.handle();

    if (typeof header !== 'string' || !KEY_PATTERN.test(header)) {
      throw new BadRequestException('Idempotency-Key must be 8-64 letters, digits or "-"');
    }
    // The body is part of the key: a key reused for a different request runs it instead of
    // replaying an unrelated response (e.g. another amount)
    const body = createHash('sha256').update(JSON.stringify(request.body ?? null)).digest('hex');
    const key = `${request.user?.id ?? 'anonymous'}:${request.method}:${request.originalUrl}:${header}:${body}`;
    return from(this.store.run(key, () => lastValueFrom(next.handle())));
  }
}
