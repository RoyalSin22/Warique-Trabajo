import { csvNumber, toCsv } from './csv';

describe('toCsv', () => {
  it('starts with a BOM, uses CRLF and quotes separators and quotes', () => {
    const csv = toCsv(['Plato', 'Monto'], [['Ají, de "gallina"', csvNumber('15.00')]]);
    expect(csv).toBe('﻿Plato,Monto\r\n"Ají, de ""gallina""",15.00\r\n');
  });

  it('neutralizes text that a spreadsheet would run as a formula', () => {
    const csv = toCsv(['x'], [['=HYPERLINK("http://evil")'], ['+51 999'], ['@SUM(A1)'], ['-1+1']]);
    expect(csv.split('\r\n').slice(1, 5)).toEqual(["\"'=HYPERLINK(\"\"http://evil\"\")\"", "'+51 999", "'@SUM(A1)", "'-1+1"]);
  });

  it('keeps negative numbers numeric and leaves empty cells empty', () => {
    expect(toCsv(['a', 'b', 'c'], [[csvNumber('-5.00'), null, 3]])).toContain('-5.00,,3\r\n');
  });
});
