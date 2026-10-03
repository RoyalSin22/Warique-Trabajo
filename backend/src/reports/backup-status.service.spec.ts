import { ConfigService } from '@nestjs/config';
import { mkdtempSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { BackupStatusService } from './backup-status.service';

describe('BackupStatusService', () => {
  const dir = mkdtempSync(join(tmpdir(), 'backup-status-'));
  const file = join(dir, 'ultimo-respaldo.json');
  const service = (path?: string) =>
    new BackupStatusService({ get: () => path } as unknown as ConfigService);
  const now = new Date('2026-10-04T12:00:00');

  it('reports "not configured" in development', async () => {
    expect(await service(undefined).read(now)).toMatchObject({ configured: false, needsAttention: false });
  });

  it('flags a missing status file', async () => {
    const status = await service(join(dir, 'missing.json')).read(now);
    expect(status).toMatchObject({ configured: true, ok: false, needsAttention: true });
  });

  it('accepts a recent, copied backup (file written with BOM by PowerShell)', async () => {
    writeFileSync(file, '﻿' + JSON.stringify({
      time: '2026-10-03T23:30:00', ok: true, file: 'warique-x.zip', sizeBytes: 2800, copied: true, error: null,
    }));
    const status = await service(file).read(now);
    expect(status).toMatchObject({ ok: true, copied: true, needsAttention: false, ageHours: 12.5 });
  });

  it('flags old, failed or not-copied backups', async () => {
    writeFileSync(file, JSON.stringify({ time: '2026-10-02T23:30:00', ok: true, copied: true }));
    expect((await service(file).read(now)).needsAttention).toBe(true); // 36.5 h

    writeFileSync(file, JSON.stringify({ time: '2026-10-03T23:30:00', ok: true, copied: false }));
    expect((await service(file).read(now)).needsAttention).toBe(true);

    writeFileSync(file, JSON.stringify({ time: '2026-10-03T23:30:00', ok: false, error: 'disk full' }));
    expect(await service(file).read(now)).toMatchObject({ ok: false, error: 'disk full', needsAttention: true });
  });
});
