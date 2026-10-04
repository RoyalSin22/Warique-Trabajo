import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface HealthStatus {
  status: 'ok' | 'degraded' | 'down';
  database: 'up' | 'down';
  /** Minutes between the MySQL session clock and UTC. Must be 0 (see README, my.ini). */
  dbUtcOffsetMinutes: number | null;
  version: string;
  uptimeSeconds: number;
}

@Injectable()
export class HealthService implements OnApplicationBootstrap {
  private readonly logger = new Logger(HealthService.name);
  private readonly version = process.env.npm_package_version ?? readPackageVersion();

  constructor(private readonly prisma: PrismaService) {}

  /** A wrong MySQL time zone silently shifts every report by hours: make it loud at startup. */
  async onApplicationBootstrap(): Promise<void> {
    const health = await this.check();
    if (health.database === 'down') {
      this.logger.error('Database unreachable at startup; /api/health will report it until it recovers');
    } else if (health.dbUtcOffsetMinutes !== 0) {
      this.logger.error(
        `MySQL time zone is not UTC (offset ${health.dbUtcOffsetMinutes} min). ` +
          `Set default-time-zone='+00:00' in my.ini and restart MySQL.`,
      );
    }
  }

  async check(): Promise<HealthStatus> {
    let offset: number | null = null;
    try {
      const rows = await this.prisma.$queryRaw<{ utc_offset_minutes: bigint | number }[]>`
        SELECT TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), NOW()) AS utc_offset_minutes`;
      offset = Number(rows[0]?.utc_offset_minutes ?? 0);
    } catch (error) {
      this.logger.error(`Database health check failed: ${String((error as Error).message ?? error).trim()}`);
    }

    const databaseUp = offset !== null;
    return {
      status: !databaseUp ? 'down' : offset === 0 ? 'ok' : 'degraded',
      database: databaseUp ? 'up' : 'down',
      dbUtcOffsetMinutes: offset,
      version: this.version,
      uptimeSeconds: Math.round(process.uptime()),
    };
  }
}

function readPackageVersion(): string {
  try {
    // dist/health -> package.json two levels up (also valid for src/health under ts-node)
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return (require('../../package.json') as { version: string }).version;
  } catch {
    return 'unknown';
  }
}
