// backend/src/supplies/supplies.service.spec.ts
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { MovementType, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { isLow, SuppliesService } from './supplies.service';

describe('SuppliesService.addMovement', () => {
  const tx = {
    $queryRaw: jest.fn(),
    supplyMovement: { create: jest.fn() },
    supply: { update: jest.fn(({ data }) => ({ id: 1, stock: data.stock, minStock: '1.000' })) },
  };
  const prisma = { $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)) };
  const realtime = { supplyUpdated: jest.fn() };
  const service = new SuppliesService(prisma as unknown as PrismaService, realtime as unknown as RealtimeService);
  const cook = { id: 3, username: 'carlos', fullName: 'Carlos', role: Role.KITCHEN };

  const givenStock = (stock: string, isActive = 1) => tx.$queryRaw.mockResolvedValue([{ id: 1, stock, isActive }]);

  beforeEach(() => jest.clearAllMocks());

  it('records a count as the difference to the current stock', async () => {
    givenStock('5.000');
    const result = await service.addMovement(1, { type: MovementType.COUNT, quantity: 3.25 }, cook);

    expect(tx.supplyMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ type: 'COUNT', quantity: '-1.750', stockAfter: '3.250', createdBy: 3 }),
    });
    expect(tx.supply.update).toHaveBeenCalledWith({ where: { id: 1 }, data: { stock: '3.250' } });
    expect(result.isLow).toBe(false);
    expect(realtime.supplyUpdated).toHaveBeenCalled();
  });

  it('subtracts waste without floating-point drift', async () => {
    givenStock('0.300');
    await service.addMovement(1, { type: MovementType.WASTE, quantity: 0.1, note: 'malogrado' }, cook);
    expect(tx.supplyMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ quantity: '-0.100', stockAfter: '0.200', note: 'malogrado' }),
    });
  });

  it('never lets the stock go negative', async () => {
    givenStock('0.500');
    await expect(service.addMovement(1, { type: MovementType.USE, quantity: 1 }, cook)).rejects.toThrow(
      ConflictException,
    );
    expect(tx.supply.update).not.toHaveBeenCalled();
  });

  it('rejects zero waste, missing and inactive supplies', async () => {
    await expect(service.addMovement(1, { type: MovementType.WASTE, quantity: 0 }, cook)).rejects.toThrow(
      BadRequestException,
    );
    tx.$queryRaw.mockResolvedValue([]);
    await expect(service.addMovement(9, { type: MovementType.COUNT, quantity: 1 }, cook)).rejects.toThrow(
      NotFoundException,
    );
    givenStock('1.000', 0);
    await expect(service.addMovement(1, { type: MovementType.COUNT, quantity: 1 }, cook)).rejects.toThrow(
      'inactive',
    );
  });
});

describe('isLow', () => {
  it('flags stock at or under the minimum, never when no minimum is set', () => {
    expect(isLow({ stock: '1.000', minStock: '1.000' })).toBe(true);
    expect(isLow({ stock: '1.001', minStock: '1.000' })).toBe(false);
    expect(isLow({ stock: '0.000', minStock: '0.000' })).toBe(false);
  });
});
