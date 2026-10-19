import { Injectable, Logger, OnModuleDestroy, OnModuleInit, Optional } from '@nestjs/common';
import { createHash } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';

interface Entry {
  expiresAt: number;
  result: Promise<unknown>;
}

/**
 * Remembers the outcome of recent requests that carried an Idempotency-Key, so a retry after a
 * network failure (the waiter taps "Enviar" again) returns the first result instead of creating
 * a second order or payment.
 *
 * Two layers: memory shares an in-flight result with concurrent retries; the database keeps each
 * successful response for the TTL, so a retry that spans a restart of the PC is still recognised.
 * Without a database (unit tests) it works from memory only.
 */
@Injectable()
export class IdempotencyStore implements OnModuleInit, OnModuleDestroy {
  static readonly TTL_MS = 15 * 60 * 1000;
  static readonly MAX_ENTRIES = 2000;
  private static readonly PRUNE_EVERY_MS = 60 * 60 * 1000;

  private readonly entries = new Map<string, Entry>();
  private readonly logger = new Logger(IdempotencyStore.name);
  private pruneTimer?: NodeJS.Timeout;

  constructor(@Optional() private readonly prisma?: PrismaService) {}

  onModuleInit(): void {
    if (!this.prisma) return;
    void this.prune();
    this.pruneTimer = setInterval(() => void this.prune(), IdempotencyStore.PRUNE_EVERY_MS);
    this.pruneTimer.unref();
  }

  onModuleDestroy(): void {
    clearInterval(this.pruneTimer);
  }

  /**
   * Runs [action] once per key. Concurrent and later calls with the same key share its result.
   * A failure is forgotten so the client can retry with the same key.
   */
  run<T>(key: string, action: () => Promise<T>, now: number = Date.now()): Promise<T> {
    this.evictExpired(now);
    const existing = this.entries.get(key);
    if (existing) return existing.result as Promise<T>;

    const result = this.runPersisted(key, action, now);
    this.entries.set(key, { expiresAt: now + IdempotencyStore.TTL_MS, result });
    result.catch(() => this.entries.delete(key));

    if (this.entries.size > IdempotencyStore.MAX_ENTRIES) {
      // Map keeps insertion order: drop the oldest key
      const oldest = this.entries.keys().next().value;
      if (oldest !== undefined) this.entries.delete(oldest);
    }
    return result;
  }

  get size(): number {
    return this.entries.size;
  }

  private async runPersisted<T>(key: string, action: () => Promise<T>, now: number): Promise<T> {
    if (!this.prisma) return action();
    const keyHash = createHash('sha256').update(key).digest('hex');

    const saved = await this.prisma.idempotencyKey
      .findFirst({
        where: { keyHash, response: { not: null }, createdAt: { gte: new Date(now - IdempotencyStore.TTL_MS) } },
        select: { response: true },
      })
      .catch(() => null); // never block the request because of this table
    if (saved?.response) return JSON.parse(saved.response) as T;

    const value = await action();
    await this.prisma.idempotencyKey
      .upsert({
        where: { keyHash },
        create: { keyHash, response: JSON.stringify(value ?? null) },
        update: { response: JSON.stringify(value ?? null), createdAt: new Date(now) },
      })
      .catch((error: Error) => this.logger.warn(`Could not persist an idempotency key: ${error.message}`));
    return value;
  }

  /** Keeps the table small: expired responses are blanked (the app account cannot DELETE). */
  private async prune(): Promise<void> {
    try {
      await this.prisma!.idempotencyKey.updateMany({
        where: { response: { not: null }, createdAt: { lt: new Date(Date.now() - IdempotencyStore.TTL_MS) } },
        data: { response: null },
      });
    } catch (error) {
      this.logger.warn(`Could not prune idempotency keys: ${(error as Error).message}`);
    }
  }

  private evictExpired(now: number): void {
    for (const [key, entry] of this.entries) {
      if (entry.expiresAt > now) break; // insertion order = expiry order
      this.entries.delete(key);
    }
  }
}
