// backend/src/menu/dishes.service.spec.ts
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { DishesService } from './dishes.service';

describe('DishesService', () => {
  const prisma = {
    category: { findUnique: jest.fn() },
    dish: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
  };
  const realtime = { dishUpdated: jest.fn(), dishesReset: jest.fn() };
  const service = new DishesService(
    prisma as unknown as PrismaService,
    realtime as unknown as RealtimeService,
  );
  const newDish = { categoryId: 1, name: 'Ceviche', price: 18.5 };

  beforeEach(() => jest.clearAllMocks());

  it('rejects a dish in a non-existent category', async () => {
    prisma.category.findUnique.mockResolvedValue(null);
    await expect(service.create(newDish)).rejects.toThrow(BadRequestException);
    expect(prisma.dish.create).not.toHaveBeenCalled();
  });

  it('rejects a dish in an inactive category', async () => {
    prisma.category.findUnique.mockResolvedValue({ isActive: false });
    await expect(service.create(newDish)).rejects.toThrow(BadRequestException);
  });

  it('creates the dish when the category is active', async () => {
    prisma.category.findUnique.mockResolvedValue({ isActive: true });
    prisma.dish.create.mockResolvedValue({ id: 10, ...newDish });

    await expect(service.create(newDish)).resolves.toMatchObject({ id: 10 });
    expect(prisma.dish.create).toHaveBeenCalledWith(expect.objectContaining({ data: newDish }));
    expect(realtime.dishUpdated).toHaveBeenCalledWith({ id: 10, ...newDish });
  });

  it('hides inactive dishes and inactive categories by default', async () => {
    prisma.dish.findMany.mockResolvedValue([]);
    await service.findAll({ includeInactive: false });
    expect(prisma.dish.findMany.mock.calls[0][0].where).toEqual({
      isActive: true,
      category: { isActive: true },
    });
  });

  it('applies filters and includes inactive records when allowed', async () => {
    prisma.dish.findMany.mockResolvedValue([]);
    await service.findAll({ categoryId: 2, available: false, includeInactive: true });
    expect(prisma.dish.findMany.mock.calls[0][0].where).toEqual({
      categoryId: 2,
      isAvailable: false,
    });
  });

  it('throws NotFound for a missing dish', async () => {
    prisma.dish.findUnique.mockResolvedValue(null);
    await expect(service.findOne(99)).rejects.toThrow(NotFoundException);
  });

  it('resets only active sold-out dishes', async () => {
    prisma.dish.updateMany.mockResolvedValue({ count: 3 });
    await expect(service.resetAvailability()).resolves.toEqual({ updated: 3 });
    expect(realtime.dishesReset).toHaveBeenCalledWith({ updated: 3 });
    expect(prisma.dish.updateMany).toHaveBeenCalledWith({
      where: { isActive: true, isAvailable: false },
      data: { isAvailable: true },
    });
  });
});
