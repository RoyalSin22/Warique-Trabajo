import { PaymentMethod } from '@prisma/client';
import { cashCsv, dailySalesCsv, expensesCsv, paymentsCsv } from './export';

const lines = (csv: string) => csv.replace(/^﻿/, '').trimEnd().split('\r\n');

describe('dailySalesCsv', () => {
  it('buckets by local business day, zero-fills and adds a total row', () => {
    const csv = dailySalesCsv({
      days: ['2026-10-01', '2026-10-02'],
      utcOffsetMinutes: -300,
      orders: [
        { createdAt: new Date('2026-10-02T04:30:00Z'), total: '10.00' }, // 23:30 on the 1st (Peru)
        { createdAt: new Date('2026-10-02T17:00:00Z'), total: '40.50' },
      ],
      payments: [
        { createdAt: new Date('2026-10-02T04:40:00Z'), method: PaymentMethod.CASH, amount: '10.00' },
        { createdAt: new Date('2026-10-02T17:30:00Z'), method: PaymentMethod.YAPE, amount: '40.50' },
      ],
      expenses: [{ date: '2026-10-02', amount: '15.25' }],
    });
    expect(lines(csv)).toEqual([
      'Fecha,Pedidos,Ventas,Cobrado efectivo,Cobrado Yape,Cobrado Plin,Total cobrado,Gastos,Ventas menos gastos',
      '2026-10-01,1,10.00,10.00,0.00,0.00,10.00,0.00,10.00',
      '2026-10-02,1,40.50,0.00,40.50,0.00,40.50,15.25,25.25',
      'TOTAL,2,50.50,10.00,40.50,0.00,50.50,15.25,35.25',
    ]);
  });
});

describe('detail exports', () => {
  it('payments carry local date/time and the operation number', () => {
    const csv = paymentsCsv(
      [
        {
          createdAt: new Date('2026-10-02T17:05:00Z'),
          orderId: 7,
          method: PaymentMethod.PLIN,
          amount: '22',
          amountReceived: null,
          changeGiven: null,
          operationNumber: '00123',
          registeredBy: 'Rosa',
          target: 'Mesa 2',
        },
      ],
      -300,
    );
    expect(lines(csv)[1]).toBe('2026-10-02,12:05,7,Mesa 2,Plin,22.00,,,00123,Rosa');
  });

  it('expenses list voided ones with their reason and the supply lines', () => {
    const csv = expensesCsv([
      {
        businessDate: '2026-10-02',
        category: 'INSUMOS',
        description: 'Mercado',
        paidWith: 'CASH',
        amount: '122.5',
        isVoid: true,
        voidReason: 'duplicado',
        createdBy: 'Dueño',
        items: [{ supplyName: 'Pescado', unit: 'KG', quantity: '5.500', cost: '110' }],
      },
    ]);
    expect(lines(csv)[1]).toBe('2026-10-02,Insumos,Mercado,Caja,122.50,ANULADO,duplicado,Pescado 5.5 kg S/ 110.00,Dueño');
  });

  it('cash counts say the result in words and keep negative differences numeric', () => {
    const csv = cashCsv(
      [
        {
          businessDate: '2026-10-02',
          openingAmount: '200',
          expectedAmount: '117.5',
          countedAmount: '114',
          difference: '-3.5',
          notes: null,
          openedBy: 'Dueño',
          closedBy: 'Dueño',
          closedAt: new Date('2026-10-02T23:10:00Z'),
        },
        {
          businessDate: '2026-10-03',
          openingAmount: '150',
          expectedAmount: null,
          countedAmount: null,
          difference: null,
          notes: null,
          openedBy: 'Dueño',
          closedBy: null,
          closedAt: null,
        },
      ],
      -300,
    );
    expect(lines(csv).slice(1)).toEqual([
      '2026-10-02,200.00,117.50,114.00,-3.50,Faltante,,Dueño,Dueño,18:10',
      '2026-10-03,150.00,,,,Sin cerrar,,Dueño,,',
    ]);
  });
});
