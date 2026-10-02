// backend/src/menu/dishes.service.ts
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { CreateDishDto, UpdateDishDto } from './dto/dish.dto';

export interface DishFilters {
  categoryId?: number;
  available?: boolean;
  includeInactive: boolean;
}

const DISH_INCLUDE = { category: { select: { id: true, name: true } } } as const;

@Injectable()
export class DishesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  findAll(filters: DishFilters) {
    return this.prisma.dish.findMany({
      where: {
        ...(filters.categoryId ? { categoryId: filters.categoryId } : {}),
        ...(filters.available !== undefined ? { isAvailable: filters.available } : {}),
        // Hidden by default: deactivated dishes and dishes whose category was deactivated
        ...(filters.includeInactive ? {} : { isActive: true, category: { isActive: true } }),
      },
      include: DISH_INCLUDE,
      orderBy: [{ category: { sortOrder: 'asc' } }, { name: 'asc' }],
    });
  }

  async findOne(id: number) {
    const dish = await this.prisma.dish.findUnique({ where: { id }, include: DISH_INCLUDE });
    if (!dish) throw new NotFoundException('Dish not found');
    return dish;
  }

  async create(dto: CreateDishDto) {
    await this.assertActiveCategory(dto.categoryId);
    const dish = await this.prisma.dish.create({ data: dto, include: DISH_INCLUDE });
    this.realtime.dishUpdated(dish);
    return dish;
  }

  /** No DELETE endpoint: deactivate with { isActive: false } to keep order history intact. */
  async update(id: number, dto: UpdateDishDto) {
    if (dto.categoryId !== undefined) await this.assertActiveCategory(dto.categoryId);
    const dish = await this.prisma.dish.update({ where: { id }, data: dto, include: DISH_INCLUDE });
    this.realtime.dishUpdated(dish);
    return dish;
  }

  /** "Agotado" toggle. Allowed for OWNER and KITCHEN; waiters' screens update instantly. */
  async setAvailability(id: number, isAvailable: boolean) {
    const dish = await this.prisma.dish.update({
      where: { id },
      data: { isAvailable },
      include: DISH_INCLUDE,
    });
    this.realtime.dishUpdated(dish);
    return dish;
  }

  /** Start-of-day helper: marks every active sold-out dish as available again. */
  async resetAvailability(): Promise<{ updated: number }> {
    const { count } = await this.prisma.dish.updateMany({
      where: { isActive: true, isAvailable: false },
      data: { isAvailable: true },
    });
    const result = { updated: count };
    this.realtime.dishesReset(result);
    return result;
  }

  private async assertActiveCategory(categoryId: number): Promise<void> {
    const category = await this.prisma.category.findUnique({
      where: { id: categoryId },
      select: { isActive: true },
    });
    if (!category?.isActive) {
      throw new BadRequestException('Category does not exist or is inactive');
    }
  }
}
