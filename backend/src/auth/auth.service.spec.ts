// backend/src/auth/auth.service.spec.ts
import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  let service: AuthService;
  const prisma = { user: { findUnique: jest.fn(), update: jest.fn() } };
  const realtime = { disconnectUser: jest.fn() };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };

  const buildUser = async (overrides: Record<string, unknown> = {}) => ({
    id: 1,
    fullName: 'Owner',
    username: 'owner',
    passwordHash: await bcrypt.hash('correct-password', 4),
    role: Role.OWNER,
    isActive: true,
    tokenVersion: 3,
    ...overrides,
  });

  beforeEach(async () => {
    jest.clearAllMocks();
    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: prisma },
        { provide: JwtService, useValue: jwt },
        { provide: RealtimeService, useValue: realtime },
      ],
    }).compile();
    service = moduleRef.get(AuthService);
  });

  it('returns a token and the user for valid credentials', async () => {
    prisma.user.findUnique.mockResolvedValue(await buildUser());

    const result = await service.login({ username: 'owner', password: 'correct-password' });

    expect(result.accessToken).toBe('signed-token');
    expect(result.user).toEqual({ id: 1, username: 'owner', fullName: 'Owner', role: Role.OWNER });
    expect(jwt.signAsync).toHaveBeenCalledWith({ sub: 1, username: 'owner', role: Role.OWNER, tv: 3 });
  });

  it('rejects an unknown username', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    await expect(service.login({ username: 'ghost', password: 'x' })).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a wrong password', async () => {
    prisma.user.findUnique.mockResolvedValue(await buildUser());
    await expect(service.login({ username: 'owner', password: 'wrong' })).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects an inactive user even with the right password', async () => {
    prisma.user.findUnique.mockResolvedValue(await buildUser({ isActive: false }));
    await expect(
      service.login({ username: 'owner', password: 'correct-password' }),
    ).rejects.toThrow(UnauthorizedException);
    expect(jwt.signAsync).not.toHaveBeenCalled();
  });

  it('changing the password ends every other session and returns a fresh token', async () => {
    prisma.user.findUnique.mockResolvedValue(await buildUser());
    prisma.user.update.mockResolvedValue(await buildUser({ tokenVersion: 4 }));

    const result = await service.changeOwnPassword(1, { currentPassword: 'correct-password', newPassword: 'New-pass-123' });

    expect(prisma.user.update.mock.calls[0][0].data.tokenVersion).toEqual({ increment: 1 });
    expect(realtime.disconnectUser).toHaveBeenCalledWith(1);
    expect(jwt.signAsync).toHaveBeenCalledWith(expect.objectContaining({ tv: 4 }));
    expect(result.accessToken).toBe('signed-token');
  });
});
