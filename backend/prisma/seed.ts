// backend/prisma/seed.ts
// Creates the first OWNER account. Idempotent: does nothing if the username exists.
import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  const username = process.env.SEED_OWNER_USERNAME;
  const password = process.env.SEED_OWNER_PASSWORD;
  const fullName = process.env.SEED_OWNER_FULL_NAME ?? 'Owner';

  if (!username || !password) {
    throw new Error('SEED_OWNER_USERNAME and SEED_OWNER_PASSWORD are required');
  }
  if (password.length < 10 || password.startsWith('CHANGE_ME')) {
    throw new Error('SEED_OWNER_PASSWORD must be a real password of at least 10 characters');
  }

  const passwordHash = await bcrypt.hash(password, 12);
  await prisma.user.upsert({
    where: { username },
    update: {},
    create: { fullName, username, passwordHash, role: Role.OWNER },
  });
  console.log(`OWNER account "${username}" is ready`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
