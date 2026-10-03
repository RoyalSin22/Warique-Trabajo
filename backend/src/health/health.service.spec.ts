import { HealthService } from './health.service';

describe('HealthService', () => {
  const build = (queryRaw: jest.Mock) =>
    new HealthService({ $queryRaw: queryRaw } as never);

  it('is ok when the database answers in UTC', async () => {
    const health = await build(jest.fn().mockResolvedValue([{ utc_offset_minutes: 0n }])).check();
    expect(health).toMatchObject({ status: 'ok', database: 'up', dbUtcOffsetMinutes: 0 });
  });

  it('is degraded when MySQL runs in local time', async () => {
    const health = await build(jest.fn().mockResolvedValue([{ utc_offset_minutes: -300 }])).check();
    expect(health).toMatchObject({ status: 'degraded', database: 'up', dbUtcOffsetMinutes: -300 });
  });

  it('is down when the database is unreachable', async () => {
    const health = await build(jest.fn().mockRejectedValue(new Error('ECONNREFUSED'))).check();
    expect(health).toMatchObject({ status: 'down', database: 'down', dbUtcOffsetMinutes: null });
  });
});
