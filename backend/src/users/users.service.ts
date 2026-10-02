// backend/src/users/users.service.ts
import { BadRequestException, Injectable } from '@nestjs/common';
import { Role } from '@prisma/client';
import { AuthenticatedUser } from '../auth/interfaces/authenticated-user.interface';
import { hashPassword } from '../auth/password.util';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';

/** password_hash is never selected, so it can never leak in a response. */
export const USER_PUBLIC_SELECT = {
  id: true,
  fullName: true,
  username: true,
  role: true,
  isActive: true,
  createdAt: true,
  updatedAt: true,
} as const;

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(includeInactive: boolean) {
    return this.prisma.user.findMany({
      where: includeInactive ? {} : { isActive: true },
      select: USER_PUBLIC_SELECT,
      orderBy: { fullName: 'asc' },
    });
  }

  async create(dto: CreateUserDto) {
    const { password, ...data } = dto;
    return this.prisma.user.create({
      data: { ...data, passwordHash: await hashPassword(password) },
      select: USER_PUBLIC_SELECT,
    });
  }

  update(id: number, dto: UpdateUserDto, actor: AuthenticatedUser) {
    // Prevents the owner from locking themselves out of the system
    const isSelf = id === actor.id;
    if (isSelf && (dto.isActive === false || (dto.role !== undefined && dto.role !== Role.OWNER))) {
      throw new BadRequestException('You cannot deactivate or demote your own account');
    }
    return this.prisma.user.update({ where: { id }, data: dto, select: USER_PUBLIC_SELECT });
  }

  async resetPassword(id: number, password: string) {
    return this.prisma.user.update({
      where: { id },
      data: { passwordHash: await hashPassword(password) },
      select: USER_PUBLIC_SELECT,
    });
  }
}
