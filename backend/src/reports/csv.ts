// backend/src/reports/csv.ts
// CSV for Excel (Peru: "." decimals, "," separator) and Google Sheets. UTF-8 with BOM so Excel
// shows "Ají de gallina" correctly instead of guessing a legacy code page.

/** A number cell: written as-is, never treated as text (a "-5.00" difference must stay numeric). */
export class CsvNumber {
  constructor(readonly value: string) {}
}

export type CsvCell = string | number | CsvNumber | null | undefined;

export const csvNumber = (value: string | number): CsvNumber => new CsvNumber(String(value));

/**
 * Text that a spreadsheet would run as a formula (=, +, -, @, tab, CR) gets a leading apostrophe:
 * a description typed as "=HYPERLINK(...)" must reach the accountant as text (CSV injection).
 */
function textCell(value: string): string {
  const safe = /^[=+\-@\t\r]/.test(value) ? `'${value}` : value;
  return /[",\r\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

function cell(value: CsvCell): string {
  if (value === null || value === undefined) return '';
  if (value instanceof CsvNumber) return value.value;
  if (typeof value === 'number') return String(value);
  return textCell(value);
}

export function toCsv(headers: string[], rows: CsvCell[][]): string {
  const lines = [headers, ...rows].map((row) => row.map(cell).join(','));
  return '﻿' + lines.join('\r\n') + '\r\n';
}
