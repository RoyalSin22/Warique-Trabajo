// backend/src/auth/interfaces/authenticated-user.interface.ts
import { Role } from '@prisma/client';

export interface JwtPayload {
  sub: number;
  username: string;
  role: Role;
  /** users.token_version when issued; tokens from before a password change are refused. Missing = 0. */
  tv?: number;
}

export interface AuthenticatedUser {
  id: number;
  username: string;
  fullName: string;
  role: Role;
}
