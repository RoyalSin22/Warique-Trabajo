// backend/src/auth/password.util.ts
import * as bcrypt from 'bcryptjs';

const BCRYPT_ROUNDS = 12;

export const hashPassword = (plain: string): Promise<string> => bcrypt.hash(plain, BCRYPT_ROUNDS);
export const verifyPassword = (plain: string, hash: string): Promise<boolean> =>
  bcrypt.compare(plain, hash);
