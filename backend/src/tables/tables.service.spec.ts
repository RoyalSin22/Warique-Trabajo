import { ConflictException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { TablesService } from './tables.service';

describe('TablesService.update', () => {
  const prisma = { order: { count: jest.fn() }, diningTable: { update: jest.fn() } };
  const service = new TablesService(prisma as unknown as PrismaService);

  beforeEach(() => jest.clearAllMocks());

  it('refuses to deactivate a table with open orders', async () => {
    prisma.order.count.mockResolvedValue(1);
    await expect(service.update(3, { isActive: false })).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.diningTable.update).not.toHaveBeenCalled();
  });

  it('deactivates a free table and renames without checking orders', async () => {
    prisma.order.count.mockResolvedValue(0);
    await service.update(3, { isActive: false });
    await service.update(3, { label: 'Terraza 1' });
    expect(prisma.order.count).toHaveBeenCalledTimes(1);
    expect(prisma.diningTable.update).toHaveBeenCalledTimes(2);
  });
});
