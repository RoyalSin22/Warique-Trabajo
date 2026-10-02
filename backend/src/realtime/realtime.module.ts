// backend/src/realtime/realtime.module.ts
import { Global, Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';

@Global()
@Module({
  providers: [RealtimeGateway, RealtimeService],
  exports: [RealtimeService],
})
export class RealtimeModule {}
