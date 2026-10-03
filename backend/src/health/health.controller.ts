import { Controller, Get, Res } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { Response } from 'express';
import { Public } from '../auth/decorators/public.decorator';
import { HealthService, HealthStatus } from './health.service';

/** Used by the install/update scripts and for monitoring. Exposes no business data. */
@Public()
@SkipThrottle()
@Controller('health')
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get()
  async check(@Res({ passthrough: true }) response: Response): Promise<HealthStatus> {
    const health = await this.healthService.check();
    if (health.status === 'down') response.status(503);
    return health;
  }
}
