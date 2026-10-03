// Creates the first OWNER account from a production build (no ts-node needed):
//   node dist/cli/create-owner.js
// Reads OWNER_USERNAME, OWNER_PASSWORD, OWNER_FULL_NAME and the database URL from the
// environment or from the .env file given by WARIQUE_ENV_FILE. Idempotent: an existing
// username is left untouched.
import { PrismaClient, Role } from '@prisma/client';
import { hashPassword } from '../auth/password.util';

export interface OwnerInput {
  username: string;
  password: string;
  fullName: string;
}

const USERNAME_PATTERN = /^[a-z0-9._-]{3,50}$/; // same rule as CreateUserDto
const OWNER_PASSWORD_MIN = 10;

export function validateOwnerInput(input: OwnerInput): string[] {
  const errors: string[] = [];
  if (!USERNAME_PATTERN.test(input.username)) {
    errors.push('username must be 3-50 characters: lowercase letters, numbers, ".", "_" or "-"');
  }
  if (input.password.length < OWNER_PASSWORD_MIN || input.password.length > 72) {
    errors.push(`password must be ${OWNER_PASSWORD_MIN}-72 characters`);
  }
  if (input.password.startsWith('CHANGE_ME')) errors.push('password must be a real password');
  if (!input.fullName.trim() || input.fullName.length > 100) {
    errors.push('full name must be 1-100 characters');
  }
  return errors;
}

/** Returns true when the account was created, false when the username already existed. */
export async function createOwner(prisma: PrismaClient, input: OwnerInput): Promise<boolean> {
  const errors = validateOwnerInput(input);
  if (errors.length > 0) throw new Error(errors.join('; '));

  const existing = await prisma.user.findUnique({ where: { username: input.username } });
  if (existing) return false;

  await prisma.user.create({
    data: {
      username: input.username,
      fullName: input.fullName.trim(),
      passwordHash: await hashPassword(input.password),
      role: Role.OWNER,
    },
  });
  return true;
}

async function main(): Promise<void> {
  const envFile = process.env.WARIQUE_ENV_FILE;
  if (envFile) process.loadEnvFile(envFile); // Node >= 21.7

  const prisma = new PrismaClient();
  try {
    const created = await createOwner(prisma, {
      username: (process.env.OWNER_USERNAME ?? '').trim().toLowerCase(),
      password: process.env.OWNER_PASSWORD ?? '',
      fullName: process.env.OWNER_FULL_NAME ?? 'Dueño',
    });
    console.log(created ? 'OWNER account created' : 'OWNER account already exists; nothing changed');
  } finally {
    await prisma.$disconnect();
  }
}

if (require.main === module) {
  main().catch((error: Error) => {
    console.error(`Could not create the OWNER account: ${error.message}`);
    process.exitCode = 1;
  });
}
