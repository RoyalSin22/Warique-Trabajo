// backend/src/common/utils/visibility.ts
import { Role } from '@prisma/client';
import { AuthenticatedUser } from '../../auth/interfaces/authenticated-user.interface';

/** Only the OWNER may list inactive (soft-deleted) records; other roles get the flag ignored. */
export const canSeeInactive = (user: AuthenticatedUser, requested?: boolean): boolean =>
  requested === true && user.role === Role.OWNER;
