import { createOwner, validateOwnerInput } from './create-owner';

describe('createOwner', () => {
  const valid = { username: 'duenio', password: 'una-clave-larga', fullName: 'Dueño' };

  it('validates username and password strength', () => {
    expect(validateOwnerInput(valid)).toEqual([]);
    expect(validateOwnerInput({ ...valid, username: 'Ab' })).toHaveLength(1);
    expect(validateOwnerInput({ ...valid, password: 'corta' })).toHaveLength(1);
    expect(validateOwnerInput({ ...valid, password: 'CHANGE_ME_please' })).toHaveLength(1);
  });

  it('creates the owner with a hashed password', async () => {
    const create = jest.fn();
    const prisma = { user: { findUnique: jest.fn().mockResolvedValue(null), create } };
    await expect(createOwner(prisma as never, valid)).resolves.toBe(true);
    const data = create.mock.calls[0][0].data;
    expect(data).toMatchObject({ username: 'duenio', role: 'OWNER' });
    expect(data.passwordHash).not.toContain(valid.password);
  });

  it('never overwrites an existing account', async () => {
    const create = jest.fn();
    const prisma = { user: { findUnique: jest.fn().mockResolvedValue({ id: 1 }), create } };
    await expect(createOwner(prisma as never, valid)).resolves.toBe(false);
    expect(create).not.toHaveBeenCalled();
  });

  it('rejects invalid input before touching the database', async () => {
    const prisma = { user: { findUnique: jest.fn(), create: jest.fn() } };
    await expect(createOwner(prisma as never, { ...valid, password: 'x' })).rejects.toThrow('password');
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });
});
