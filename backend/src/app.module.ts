// backend/src/app.module.ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AuthModule } from './auth/auth.module';
import { PrismaExceptionFilter } from './common/filters/prisma-exception.filter';
import { validateEnv } from './config/env.validation';
import { HealthModule } from './health/health.module';
import { MenuModule } from './menu/menu.module';
import { OrdersModule } from './orders/orders.module';
import { PrismaModule } from './prisma/prisma.module';
import { RealtimeModule } from './realtime/realtime.module';
import { ReportsModule } from './reports/reports.module';
import { TablesModule } from './tables/tables.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // Windows service: the .env lives outside the app folder so updates never overwrite it
      envFilePath: process.env.WARIQUE_ENV_FILE ?? '.env',
      validate: validateEnv,
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    PrismaModule,
    HealthModule,
    RealtimeModule,
    AuthModule,
    UsersModule,
    MenuModule,
    TablesModule,
    OrdersModule,
    ReportsModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_FILTER, useClass: PrismaExceptionFilter },
  ],
})
export class AppModule {}
