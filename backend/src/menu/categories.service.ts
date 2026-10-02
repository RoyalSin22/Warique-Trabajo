// backend/src/menu/categories.service.ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCategoryDto, UpdateCategoryDto } from './dto/category.dto';

@Injectable()
export class CategoriesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(includeInactive: boolean) {
    return this.prisma.category.findMany({
      where: includeInactive ? {} : { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  create(dto: CreateCategoryDto) {
    return this.prisma.category.create({ data: dto });
  }

  /** No DELETE endpoint: deactivate with { isActive: false } to keep order history intact. */
  update(id: number, dto: UpdateCategoryDto) {
    return this.prisma.category.update({ where: { id }, data: dto });
  }
}
