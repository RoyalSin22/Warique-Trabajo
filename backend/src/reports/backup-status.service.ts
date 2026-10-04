import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { readFile } from 'fs/promises';

/** A daily backup older than this means at least one run was missed. */
const STALE_AFTER_HOURS = 26;

export interface BackupStatus {
  /** false when BACKUP_STATUS_FILE is not set (development) */
  configured: boolean;
  /** Last run finished without errors */
  ok: boolean;
  /** Needs the owner's attention: failed, missing, too old or not copied off the PC */
  needsAttention: boolean;
  time: string | null;
  ageHours: number | null;
  file: string | null;
  sizeBytes: number | null;
  copied: boolean;
  error: string | null;
}

interface StatusFile {
  time?: string;
  ok?: boolean;
  file?: string | null;
  sizeBytes?: number;
  copied?: boolean;
  error?: string | null;
}

/**
 * Reads the status file written by deploy/windows/backup.ps1. The backups themselves live in a
 * folder the service account cannot read; only this summary is shared with it.
 */
@Injectable()
export class BackupStatusService {
  constructor(private readonly config: ConfigService) {}

  async read(now: Date = new Date()): Promise<BackupStatus> {
    const path = this.config.get<string>('BACKUP_STATUS_FILE');
    if (!path) return emptyStatus(false, null);

    let status: StatusFile;
    try {
      // backup.ps1 writes UTF-8; strip a BOM just in case
      status = JSON.parse((await readFile(path, 'utf8')).replace(/^﻿/, '')) as StatusFile;
    } catch {
      return emptyStatus(true, 'No hay registro de respaldos todavía');
    }

    // backup.ps1 writes local time without offset ("2026-10-03T23:30:05"), same zone as the PC
    const time = status.time ? new Date(status.time) : null;
    const ageHours =
      time && !Number.isNaN(time.getTime())
        ? Math.round(((now.getTime() - time.getTime()) / 3_600_000) * 10) / 10
        : null;
    const ok = status.ok === true;
    const copied = status.copied === true;

    return {
      configured: true,
      ok,
      needsAttention: !ok || !copied || ageHours === null || ageHours > STALE_AFTER_HOURS,
      time: time ? time.toISOString() : null,
      ageHours,
      file: status.file ?? null,
      sizeBytes: status.sizeBytes ?? null,
      copied,
      error: status.error ?? null,
    };
  }
}

function emptyStatus(configured: boolean, error: string | null): BackupStatus {
  return {
    configured,
    ok: false,
    needsAttention: configured,
    time: null,
    ageHours: null,
    file: null,
    sizeBytes: null,
    copied: false,
    error,
  };
}
