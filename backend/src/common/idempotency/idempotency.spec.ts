import { BadRequestException, CallHandler, ExecutionContext } from '@nestjs/common';
import { lastValueFrom, of, throwError } from 'rxjs';
import { IdempotencyInterceptor } from './idempotency.interceptor';
import { IdempotencyStore } from './idempotency.store';

describe('IdempotencyStore', () => {
  it('runs the action once and shares the result with concurrent and later retries', async () => {
    const store = new IdempotencyStore();
    let calls = 0;
    const action = () => new Promise<number>((resolve) => setTimeout(() => resolve(++calls), 5));

    const [first, concurrent] = await Promise.all([store.run('k', action), store.run('k', action)]);
    const later = await store.run('k', action);

    expect([first, concurrent, later]).toEqual([1, 1, 1]);
    expect(calls).toBe(1);
  });

  it('forgets failures so the client can retry with the same key', async () => {
    const store = new IdempotencyStore();
    await expect(store.run('k', () => Promise.reject(new Error('db down')))).rejects.toThrow('db down');
    await expect(store.run('k', () => Promise.resolve('ok'))).resolves.toBe('ok');
  });

  it('expires keys after the TTL', async () => {
    const store = new IdempotencyStore();
    await store.run('k', () => Promise.resolve(1), 0);
    await expect(store.run('k', () => Promise.resolve(2), IdempotencyStore.TTL_MS + 1)).resolves.toBe(2);
  });
});

describe('IdempotencyInterceptor', () => {
  const contextFor = (headers: Record<string, unknown>, url = '/api/orders', userId = 7) =>
    ({
      switchToHttp: () => ({
        getRequest: () => ({ headers, method: 'POST', originalUrl: url, user: { id: userId } }),
      }),
    }) as unknown as ExecutionContext;

  const handler = (value: unknown): CallHandler & { calls: number } => {
    const h = { calls: 0, handle: () => (h.calls++, of(value)) };
    return h;
  };

  it('passes through requests without the header', async () => {
    const interceptor = new IdempotencyInterceptor(new IdempotencyStore());
    const next = handler('order');
    await lastValueFrom(interceptor.intercept(contextFor({}), next));
    await lastValueFrom(interceptor.intercept(contextFor({}), next));
    expect(next.calls).toBe(2);
  });

  it('replays the first response for a retried key, scoped by user and URL', async () => {
    const interceptor = new IdempotencyInterceptor(new IdempotencyStore());
    const next = handler({ id: 1 });
    const headers = { 'idempotency-key': 'a1b2c3d4-retry' };

    await lastValueFrom(interceptor.intercept(contextFor(headers), next));
    const replay = await lastValueFrom(interceptor.intercept(contextFor(headers), next));
    await lastValueFrom(interceptor.intercept(contextFor(headers, '/api/orders/5/payments'), next));
    await lastValueFrom(interceptor.intercept(contextFor(headers, '/api/orders', 8), next));

    expect(replay).toEqual({ id: 1 });
    expect(next.calls).toBe(3);
  });

  it('rejects malformed keys and does not cache errors', async () => {
    const interceptor = new IdempotencyInterceptor(new IdempotencyStore());
    expect(() => interceptor.intercept(contextFor({ 'idempotency-key': 'x' }), handler(1))).toThrow(
      BadRequestException,
    );

    const headers = { 'idempotency-key': 'retry-after-error' };
    const failing = { handle: () => throwError(() => new Error('conflict')) };
    await expect(lastValueFrom(interceptor.intercept(contextFor(headers), failing))).rejects.toThrow();
    await expect(lastValueFrom(interceptor.intercept(contextFor(headers), handler('ok')))).resolves.toBe('ok');
  });
});
