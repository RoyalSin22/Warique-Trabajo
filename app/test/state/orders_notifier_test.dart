import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/data/realtime_client.dart';
import 'package:warique_app/models/order.dart';
import 'package:warique_app/models/user.dart';
import 'package:warique_app/state/orders.dart';

import '../support/container.dart';
import '../support/fixtures.dart';

void main() {
  late FakeRealtime realtime;
  late List<Map<String, dynamic>> serverOrders;
  late RecordingHttp http;
  late ProviderContainer container;

  setUp(() {
    realtime = FakeRealtime();
    serverOrders = [orderJson(id: 1)];
    http = RecordingHttp((request) => (200, serverOrders));
    container = ProviderContainer(
      overrides: sessionOverrides(role: Role.kitchen, http: http, realtime: realtime),
    );
    addTearDown(container.dispose);
  });

  Future<List<Order>> load() async {
    container.listen(ordersProvider, (_, _) {}); // keep the autoDispose provider alive
    return container.read(ordersProvider.future);
  }

  test('loads today\'s orders', () async {
    final orders = await load();
    expect(orders.single.id, 1);
    expect(http.requests.single.url.path, '/api/orders');
  });

  test('applies order.created and order.updated events', () async {
    await load();
    realtime.emit(RealtimeEvent.orderCreated, orderJson(id: 2, createdAt: '2026-10-03T15:01:00.000Z'));
    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(id: 1, status: 'IN_PREPARATION', updatedAt: '2026-10-03T15:02:00.000Z'),
    );
    await pumpEventQueue();

    final orders = container.read(ordersProvider).value!;
    expect(orders.map((o) => o.id), [1, 2]); // FIFO
    expect(orders.first.status, OrderStatus.inPreparation);
  });

  test('ignores an event older than the copy it already has', () async {
    await load();
    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(id: 1, status: 'READY', updatedAt: '2026-10-03T15:05:00.000Z'),
    );
    realtime.emit(
      RealtimeEvent.orderUpdated,
      orderJson(id: 1, status: 'IN_PREPARATION', updatedAt: '2026-10-03T15:02:00.000Z'),
    );
    await pumpEventQueue();

    expect(container.read(ordersProvider).value!.single.status, OrderStatus.ready);
  });

  test('keeps events that arrive while the first load is in flight', () async {
    final gate = Completer<void>();
    http = RecordingHttp((request) async {
      await gate.future;
      return (200, [orderJson(id: 1)]);
    });
    container = ProviderContainer(
      overrides: sessionOverrides(role: Role.kitchen, http: http, realtime: realtime),
    );
    addTearDown(container.dispose);

    container.listen(ordersProvider, (_, _) {});
    final future = container.read(ordersProvider.future);
    await pumpEventQueue();
    realtime.emit(RealtimeEvent.orderCreated, orderJson(id: 7, createdAt: '2026-10-03T15:09:00.000Z'));
    gate.complete();

    expect((await future).map((o) => o.id), [1, 7]);
  });

  test('reloads after reconnecting to recover missed events', () async {
    await load();
    serverOrders = [orderJson(id: 1), orderJson(id: 3, createdAt: '2026-10-03T15:03:00.000Z')];
    realtime.connectedController.add(true);
    await pumpEventQueue();

    expect(container.read(ordersProvider).value!.map((o) => o.id), [1, 3]);
    expect(http.requests, hasLength(2));
  });
}
