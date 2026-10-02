// backend/src/common/filters/prisma-exception.filter.spec.ts
import { ArgumentsHost, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaExceptionFilter } from './prisma-exception.filter';

describe('PrismaExceptionFilter', () => {
  const json = jest.fn();
  const status = jest.fn(() => ({ json }));
  const host = {
    switchToHttp: () => ({ getResponse: () => ({ status }) }),
  } as unknown as ArgumentsHost;
  const filter = new PrismaExceptionFilter();
  const prismaError = (code: string) =>
    new Prisma.PrismaClientKnownRequestError('db detail', { code, clientVersion: '6' });

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
  });

  it.each([
    ['P2002', 409],
    ['P2003', 400],
    ['P2025', 404],
  ])('maps %s to HTTP %i', (code, httpStatus) => {
    filter.catch(prismaError(code), host);
    expect(status).toHaveBeenCalledWith(httpStatus);
  });

  it('returns a generic 500 for unmapped codes without leaking details', () => {
    filter.catch(prismaError('P2999'), host);
    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({ statusCode: 500, message: 'Internal server error' });
  });
});
