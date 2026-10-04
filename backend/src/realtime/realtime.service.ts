// backend/src/realtime/realtime.service.ts
import { Injectable } from '@nestjs/common';
import { RealtimeGateway, STAFF_ROOM, userRoom } from './realtime.gateway';

export const RealtimeEvent = {
  ORDER_CREATED: 'order.created',
  ORDER_UPDATED: 'order.updated',
  DISH_UPDATED: 'dish.updated',
  DISHES_RESET: 'dishes.reset',
  SUPPLY_UPDATED: 'supply.updated',
} as const;

/** Thin facade so business services never depend on Socket.IO directly. */
@Injectable()
export class RealtimeService {
  constructor(private readonly gateway: RealtimeGateway) {}

  orderCreated(order: unknown): void {
    this.emit(RealtimeEvent.ORDER_CREATED, order);
  }

  orderUpdated(order: unknown): void {
    this.emit(RealtimeEvent.ORDER_UPDATED, order);
  }

  dishUpdated(dish: unknown): void {
    this.emit(RealtimeEvent.DISH_UPDATED, dish);
  }

  dishesReset(result: { updated: number }): void {
    this.emit(RealtimeEvent.DISHES_RESET, result);
  }

  supplyUpdated(supply: unknown): void {
    this.emit(RealtimeEvent.SUPPLY_UPDATED, supply);
  }

  /** Closes every live connection of a user (e.g. just deactivated). */
  disconnectUser(userId: number): void {
    this.gateway.server?.in(userRoom(userId)).disconnectSockets(true);
  }

  private emit(event: string, payload: unknown): void {
    this.gateway.server?.to(STAFF_ROOM).emit(event, payload);
  }
}
