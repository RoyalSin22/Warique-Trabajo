import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { existsSync } from 'fs';
import helmet from 'helmet';
import { join, resolve } from 'path';
import { AppModule } from './app.module';
import { SocketIoAdapter } from './realtime/socket-io.adapter';

/**
 * Content-Security-Policy compatible with the Flutter web build:
 * - 'wasm-unsafe-eval': CanvasKit is WebAssembly
 * - fonts are bundled (`flutter build web --no-web-resources-cdn`): nothing is loaded from the
 *   internet, so the app keeps working if the restaurant's connection drops
 * - no upgrade-insecure-requests: the app is served over plain HTTP on the local network,
 *   and that directive would make the browser request everything over HTTPS
 */
const FLUTTER_CSP = {
  useDefaults: false,
  directives: {
    defaultSrc: ["'self'"],
    scriptSrc: ["'self'", "'wasm-unsafe-eval'"],
    styleSrc: ["'self'", "'unsafe-inline'"],
    imgSrc: ["'self'", 'data:', 'blob:'],
    fontSrc: ["'self'", 'data:'],
    // ws:/wss: explicitly: older browsers do not match WebSockets with 'self'
    connectSrc: ["'self'", 'ws:', 'wss:'],
    workerSrc: ["'self'", 'blob:'],
    objectSrc: ["'none'"],
    baseUri: ["'self'"],
    frameAncestors: ["'none'"],
    formAction: ["'self'"],
  },
};

/** Flutter web build to serve at `/`: WEB_DIR, or `<backend>/public` when present. */
function resolveWebDir(configured: string | undefined): string | null {
  const dir = configured ? resolve(configured) : join(__dirname, '..', 'public');
  return existsSync(join(dir, 'index.html')) ? dir : null;
}

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  const allowedOrigins = (config.get<string>('CORS_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.use(
    helmet({
      contentSecurityPolicy: FLUTTER_CSP,
      // HSTS on a plain-HTTP LAN server would only confuse browsers if HTTPS is added later
      strictTransportSecurity: false,
      // Ignored by browsers on plain HTTP (non-localhost); disabled to avoid console noise
      crossOriginOpenerPolicy: false,
    }),
  );
  app.enableCors({ origin: allowedOrigins });
  app.useWebSocketAdapter(new SocketIoAdapter(app, allowedOrigins));
  app.setGlobalPrefix('api');
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.enableShutdownHooks();

  // Same origin for app and API: no CORS setup needed and a single port in the firewall
  const webDir = resolveWebDir(config.get<string>('WEB_DIR'));
  if (webDir) {
    app.useStaticAssets(webDir, {
      index: 'index.html',
      // File names are not hashed: always revalidate (ETag) so an update reaches every device
      setHeaders: (response) => response.setHeader('Cache-Control', 'no-cache'),
    });
    logger.log(`Serving web app from ${webDir}`);
  } else {
    logger.warn('No web build found (WEB_DIR or ./public): serving the API only');
  }

  const port = Number(config.get('PORT') ?? 3000);
  // 0.0.0.0 -> reachable from phones/tablets on the local network
  await app.listen(port, '0.0.0.0');
}

void bootstrap();
