// backend/src/users/users.service.spec.ts
import { BadRequestException } from '@nestjs/common';
import { Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { USER_PUBLIC_SELECT, UsersService } from './users.service';

describe('UsersService', () => {
  const prisma = { user: { create: jest.fn(), update: jest.fn(), findMany: jest.fn() } };
  const realtime = { disconnectUser: jest.fn() };
  const service = new UsersService(prisma as unknown as PrismaService, realtime as unknown as RealtimeService);
  const owner = { id: 1, username: 'owner', fullName: 'Owner', role: Role.OWNER };

  beforeEach(() => jest.clearAllMocks());

  it('stores a bcrypt hash, never the plain password', async () => {
    await service.create({ fullName: 'Ana', username: 'ana', password: 'secret-123', role: Role.WAITER });

    const { data, select } = prisma.user.create.mock.calls[0][0];
    expect(data.password).toBeUndefined();
    expect(data.passwordHash).not.toBe('secret-123');
    await expect(bcrypt.compare('secret-123', data.passwordHash)).resolves.toBe(true);
    expect(select).toBe(USER_PUBLIC_SELECT);
    expect(select).not.toHaveProperty('passwordHash');
  });

  it('blocks the owner from deactivating their own account', () => {
    expect(() => service.update(1, { isActive: false }, owner)).toThrow(BadRequestException);
  });

  it('blocks the owner from demoting their own account', () => {
    expect(() => service.update(1, { role: Role.WAITER }, owner)).toThrow(BadRequestException);
  });

  it('allows the owner to deactivate another user', async () => {
    prisma.user.update.mockResolvedValue({ id: 2, isActive: false });
    await service.update(2, { isActive: false }, owner);
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 2 }, data: { isActive: false } }),
    );
  });

  it('closes the live connections of a deactivated user', async () => {
    prisma.user.update.mockResolvedValue({ id: 2 });
    await service.update(2, { isActive: false }, owner);
    expect(realtime.disconnectUser).toHaveBeenCalledWith(2);

    realtime.disconnectUser.mockClear();
    await service.update(2, { fullName: 'Ana María' }, owner);
    expect(realtime.disconnectUser).not.toHaveBeenCalled();
  });
});
