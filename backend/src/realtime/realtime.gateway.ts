// backend/src/realtime/realtime.gateway.ts
import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, OnGatewayDisconnect, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Role } from '@prisma/client';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/interfaces/authenticated-user.interface';
import { PrismaService } from '../prisma/prisma.service';

export const STAFF_ROOM = 'staff';

/** Per-user room, used to drop the connections of a deactivated account. */
export const userRoom = (userId: number): string => `user:${userId}`;

/** Per-role room: the kitchen gets orders without payment details. */
export const roleRoom = (role: Role): string => `role:${role}`;

/**
 * Clients connect with: io(url, { auth: { token: '<JWT>' } }).
 * Unauthenticated, inactive or outdated (password changed) tokens are disconnected immediately,
 * and every socket is closed when its token expires (the client then signs in again).
 */
@WebSocketGateway()
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  private readonly expiryTimers = new Map<string, NodeJS.Timeout>();

  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    try {
      const token: unknown = client.handshake.auth?.token;
      if (typeof token !== 'string') throw new Error('Missing token');

      const payload = await this.jwt.verifyAsync<JwtPayload & { exp?: number }>(token);
      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { isActive: true, role: true, tokenVersion: true },
      });
      if (!user?.isActive) throw new Error('Inactive user');
      if ((payload.tv ?? 0) !== user.tokenVersion) throw new Error('Outdated token');

      await client.join([STAFF_ROOM, userRoom(payload.sub), roleRoom(user.role)]);
      // A password change between the check and the join would have missed this socket
      const after = await this.prisma.user.findUnique({ where: { id: payload.sub }, select: { tokenVersion: true, isActive: true } });
      if (!after?.isActive || after.tokenVersion !== user.tokenVersion) throw new Error('Session changed while connecting');
      if (payload.exp) {
        const ms = Math.max(payload.exp * 1000 - Date.now(), 0);
        // setTimeout caps at ~24.8 days; tokens last hours
        this.expiryTimers.set(client.id, setTimeout(() => client.disconnect(true), Math.min(ms, 2_147_000_000)));
      }
    } catch (error) {
      this.logger.warn(`Socket rejected: ${(error as Error).message}`);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    clearTimeout(this.expiryTimers.get(client.id));
    this.expiryTimers.delete(client.id);
  }
}
