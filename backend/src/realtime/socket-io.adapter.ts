// backend/src/realtime/socket-io.adapter.ts
import { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { ServerOptions } from 'socket.io';

/** Applies CORS from env at runtime (gateway decorators are evaluated before .env is loaded). */
export class SocketIoAdapter extends IoAdapter {
  constructor(
    app: INestApplicationContext,
    private readonly allowedOrigins: string[],
  ) {
    super(app);
  }

  override createIOServer(port: number, options?: ServerOptions) {
    return super.createIOServer(port, { ...options, cors: { origin: this.allowedOrigins } });
  }
}
