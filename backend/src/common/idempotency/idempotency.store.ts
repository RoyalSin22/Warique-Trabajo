import { Injectable } from '@nestjs/common';

interface Entry {
  expiresAt: number;
  result: Promise<unknown>;
}

/**
 * Remembers the outcome of recent requests that carried an Idempotency-Key, so a retry after a
 * network failure (the waiter taps "Enviar" again) returns the first result instead of creating
 * a second order or payment.
 *
 * In memory on purpose: the API is a single process and retries happen within seconds. A restart
 * forgets the keys, which only matters for a retry that spans the restart.
 */
@Injectable()
export class IdempotencyStore {
  static readonly TTL_MS = 15 * 60 * 1000;
  static readonly MAX_ENTRIES = 2000;

  private readonly entries = new Map<string, Entry>();

  /**
   * Runs [action] once per key. Concurrent and later calls with the same key share its result.
   * A failure is forgotten so the client can retry with the same key.
   */
  run<T>(key: string, action: () => Promise<T>, now: number = Date.now()): Promise<T> {
    this.evictExpired(now);
    const existing = this.entries.get(key);
    if (existing) return existing.result as Promise<T>;

    const result = action();
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

  private evictExpired(now: number): void {
    for (const [key, entry] of this.entries) {
      if (entry.expiresAt > now) break; // insertion order = expiry order
      this.entries.delete(key);
    }
  }
}
