// backend/src/realtime/realtime.service.spec.ts
import { Role } from '@prisma/client';
import { RealtimeGateway, roleRoom } from './realtime.gateway';
import { RealtimeService } from './realtime.service';

describe('RealtimeService', () => {
  const sent: { rooms: string | string[]; event: string; payload: unknown }[] = [];
  const server = {
    to: (rooms: string | string[]) => ({ emit: (event: string, payload: unknown) => sent.push({ rooms, event, payload }) }),
  };
  const service = new RealtimeService({ server } as unknown as RealtimeGateway);

  it('sends the kitchen orders without their payments', () => {
    service.orderUpdated({ id: 1, items: [], payments: [{ operationNumber: '123456' }] });

    const staff = sent.find((m) => Array.isArray(m.rooms));
    const kitchen = sent.find((m) => m.rooms === roleRoom(Role.KITCHEN));
    expect(staff?.rooms).toEqual([roleRoom(Role.OWNER), roleRoom(Role.WAITER)]);
    expect(staff?.payload).toHaveProperty('payments');
    expect(kitchen?.payload).toEqual({ id: 1, items: [] });
  });
});
