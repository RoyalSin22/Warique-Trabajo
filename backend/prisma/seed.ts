// Development helper: creates the first OWNER from SEED_OWNER_* variables (`npm run db:seed`).
// Production installs use the compiled equivalent: node dist/cli/create-owner.js
import { PrismaClient } from '@prisma/client';
import { createOwner } from '../src/cli/create-owner';

const prisma = new PrismaClient();

createOwner(prisma, {
  username: process.env.SEED_OWNER_USERNAME ?? '',
  password: process.env.SEED_OWNER_PASSWORD ?? '',
  fullName: process.env.SEED_OWNER_FULL_NAME ?? 'Owner',
})
  .then((created) => console.log(created ? 'OWNER account created' : 'OWNER account already exists'))
  .catch((error: Error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
