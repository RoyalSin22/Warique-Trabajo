// backend/src/common/filters/prisma-exception.filter.ts
import { ArgumentsHost, Catch, ExceptionFilter, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';

const PRISMA_ERROR_MAP: Record<string, { status: number; message: string }> = {
  P2002: { status: HttpStatus.CONFLICT, message: 'A record with the same unique value already exists' },
  P2003: { status: HttpStatus.BAD_REQUEST, message: 'Related record does not exist' },
  P2025: { status: HttpStatus.NOT_FOUND, message: 'Record not found' },
  // Two people on the same order at the same instant (row lock wait, deadlock): just retry
  P2028: { status: HttpStatus.CONFLICT, message: 'The record is busy, try again' },
  P2034: { status: HttpStatus.CONFLICT, message: 'The record is busy, try again' },
};

/** Maps known Prisma errors to HTTP codes without leaking database details to the client. */
@Catch(Prisma.PrismaClientKnownRequestError, Prisma.PrismaClientValidationError)
export class PrismaExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(PrismaExceptionFilter.name);

  catch(
    exception: Prisma.PrismaClientKnownRequestError | Prisma.PrismaClientValidationError,
    host: ArgumentsHost,
  ): void {
    const response = host.switchToHttp().getResponse<Response>();
    // A value the database cannot take (e.g. an id beyond the INT range): the request is wrong
    if (exception instanceof Prisma.PrismaClientValidationError) {
      response.status(HttpStatus.BAD_REQUEST).json({ statusCode: HttpStatus.BAD_REQUEST, message: 'Invalid request' });
      return;
    }
    const mapped = PRISMA_ERROR_MAP[exception.code];

    if (!mapped) {
      this.logger.error(`Unhandled Prisma error ${exception.code}: ${exception.message}`);
      response
        .status(HttpStatus.INTERNAL_SERVER_ERROR)
        .json({ statusCode: HttpStatus.INTERNAL_SERVER_ERROR, message: 'Internal server error' });
      return;
    }

    response.status(mapped.status).json({ statusCode: mapped.status, message: mapped.message });
  }
}
