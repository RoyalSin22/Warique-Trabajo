/// Spanish date labels without pulling in `intl` for two arrays.
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Business day key used by the API: `YYYY-MM-DD` of the device's local date.
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// "sábado 3 de octubre"
String longDayLabel(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} de ${_months[date.month - 1]}';

/// "hace 3 h", "hace 2 días"
String ageLabel(double hours) {
  if (hours < 1) return 'hace menos de 1 h';
  if (hours < 48) return 'hace ${hours.round()} h';
  return 'hace ${(hours / 24).floor()} días';
}
