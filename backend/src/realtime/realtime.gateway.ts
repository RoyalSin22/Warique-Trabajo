// backend/src/realtime/realtime.gateway.ts
import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/interfaces/authenticated-user.interface';
import { PrismaService } from '../prisma/prisma.service';

export const STAFF_ROOM = 'staff';

/** Per-user room, used to drop the connections of a deactivated account. */
export const userRoom = (userId: number): string => `user:${userId}`;

/**
 * Clients connect with: io(url, { auth: { token: '<JWT>' } }).
 * Unauthenticated or inactive users are disconnected immediately.
 */
@WebSocketGateway()
export class RealtimeGateway implements OnGatewayConnection {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    try {
      const token: unknown = client.handshake.auth?.token;
      if (typeof token !== 'string') throw new Error('Missing token');

      const payload = await this.jwt.verifyAsync<JwtPayload>(token);
      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { isActive: true },
      });
      if (!user?.isActive) throw new Error('Inactive user');

      await client.join([STAFF_ROOM, userRoom(payload.sub)]);
    } catch (error) {
      this.logger.warn(`Socket rejected: ${(error as Error).message}`);
      client.disconnect(true);
    }
  }
}
