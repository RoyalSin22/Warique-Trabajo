// backend/src/tables/tables.service.ts
import { ConflictException, Injectable } from '@nestjs/common';
import { OrderStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTableDto, UpdateTableDto } from './dto/table.dto';

@Injectable()
export class TablesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(includeInactive: boolean) {
    return this.prisma.diningTable.findMany({
      where: includeInactive ? {} : { isActive: true },
      orderBy: { id: 'asc' }, // creation order: avoids "Mesa 10" sorting before "Mesa 2"
    });
  }

  create(dto: CreateTableDto) {
    return this.prisma.diningTable.create({ data: dto });
  }

  async update(id: number, dto: UpdateTableDto) {
    if (dto.isActive === false) {
      // A table with an open order would vanish from the waiters' table picker mid-service
      const openOrders = await this.prisma.order.count({
        where: {
          tableId: id,
          status: { in: [OrderStatus.PENDING, OrderStatus.IN_PREPARATION, OrderStatus.READY] },
        },
      });
      if (openOrders > 0) {
        throw new ConflictException('The table has open orders');
      }
    }
    return this.prisma.diningTable.update({ where: { id }, data: dto });
  }
}
