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

const _weekdayShort = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _weekdayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const _monthShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];

/// "L".."D" for ISO weekday 1..7
String weekdayInitial(int weekday) => _weekdayShort[weekday - 1];

/// "Lunes".."Domingo" for ISO weekday 1..7
String weekdayName(int weekday) => _weekdayNames[weekday - 1];

/// "3 oct"
String shortDayLabel(DateTime date) => '${date.day} ${_monthShort[date.month - 1]}';

/// "sáb 3 oct"
String mediumDayLabel(DateTime date) =>
    '${_weekdays[date.weekday - 1].substring(0, 3)} ${date.day} ${_monthShort[date.month - 1]}';

/// "los sábados", "los viernes": only sábado and domingo change in the plural
String weekdayPlural(int weekday) {
  final name = _weekdayNames[weekday - 1].toLowerCase();
  return weekday >= 6 ? '${name}s' : name;
}
