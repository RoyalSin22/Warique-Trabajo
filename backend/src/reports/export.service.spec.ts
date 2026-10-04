import { ForbiddenException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ExportService } from './export.service';

describe('ExportService links', () => {
  const jwt = new JwtService({ secret: 'session-secret' });
  const config = { get: () => -300, getOrThrow: () => 'session-secret' } as unknown as ConfigService;
  const findUnique = jest.fn();
  const prisma = {
    user: { findUnique },
    cashSession: { findMany: jest.fn().mockResolvedValue([]) },
  } as unknown as PrismaService;
  const service = new ExportService(prisma, jwt, config);
  const owner = { id: 1, username: 'owner', fullName: 'Dueño', role: Role.OWNER };

  beforeEach(() => findUnique.mockResolvedValue({ role: Role.OWNER, isActive: true }));

  const tokenOf = async () => (await service.createLink('arqueos', '2026-10-01', '2026-10-03', owner)).url.split('/').pop()!;

  it('signs a short-lived link that downloads a named CSV', async () => {
    const link = await service.createLink('arqueos', '2026-10-01', '2026-10-03', owner);
    expect(link).toMatchObject({ fileName: 'warique-arqueos-2026-10-01_a_2026-10-03.csv', expiresInSeconds: 120 });
    const file = await service.download(link.url.split('/').pop()!);
    expect(file.fileName).toBe(link.fileName);
    expect(file.content.startsWith('﻿Fecha,Fondo inicial')).toBe(true);
  });

  it('a link is not a session token, and a session token is not a link', async () => {
    await expect(jwt.verifyAsync(await tokenOf())).rejects.toThrow(); // what JwtAuthGuard does
    const session = await jwt.signAsync({ sub: 1, username: 'owner', role: Role.OWNER });
    await expect(service.download(session)).rejects.toThrow(ForbiddenException);
  });

  it('dies with its owner: deactivated or demoted accounts cannot download', async () => {
    const token = await tokenOf();
    findUnique.mockResolvedValue({ role: Role.OWNER, isActive: false });
    await expect(service.download(token)).rejects.toThrow(ForbiddenException);
    findUnique.mockResolvedValue({ role: Role.WAITER, isActive: true });
    await expect(service.download(token)).rejects.toThrow(ForbiddenException);
  });

  it('rejects inverted and too long ranges before signing', async () => {
    await expect(service.createLink('ventas', '2026-10-03', '2026-10-01', owner)).rejects.toThrow('from must be');
    await expect(service.createLink('ventas', '2025-01-01', '2026-10-01', owner)).rejects.toThrow('366');
    await expect(service.createLink('ventas', '2026-02-30', '2026-03-01', owner)).rejects.toThrow('Invalid date');
  });
});
