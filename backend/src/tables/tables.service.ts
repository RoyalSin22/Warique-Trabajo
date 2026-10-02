// backend/src/tables/tables.service.ts
import { Injectable } from '@nestjs/common';
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

  update(id: number, dto: UpdateTableDto) {
    return this.prisma.diningTable.update({ where: { id }, data: dto });
  }
}
