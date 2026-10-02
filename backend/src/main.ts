// backend/src/main.ts
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { SocketIoAdapter } from './realtime/socket-io.adapter';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);

  const allowedOrigins = (config.get<string>('CORS_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.use(helmet());
  app.enableCors({ origin: allowedOrigins });
  app.useWebSocketAdapter(new SocketIoAdapter(app, allowedOrigins));
  app.setGlobalPrefix('api');
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.enableShutdownHooks();

  const port = Number(config.get('PORT') ?? 3000);
  // 0.0.0.0 -> reachable from phones/tablets on the local network
  await app.listen(port, '0.0.0.0');
}

void bootstrap();
