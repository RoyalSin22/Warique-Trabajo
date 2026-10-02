// backend/src/auth/interfaces/authenticated-user.interface.ts
import { Role } from '@prisma/client';

export interface JwtPayload {
  sub: number;
  username: string;
  role: Role;
}

export interface AuthenticatedUser {
  id: number;
  username: string;
  fullName: string;
  role: Role;
}
