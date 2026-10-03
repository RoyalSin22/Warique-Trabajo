/// Stock quantity as integer thousandths, mirroring the backend (`common/utils/quantity.ts`):
/// 2.5 kg = 2500. Parsed digit by digit, like [Money], so "0.1" + "0.2" is exactly "0.3".
class Quantity implements Comparable<Quantity> {
  const Quantity(this.milli);

  final int milli;

  static const zero = Quantity(0);

  static final _pattern = RegExp(r'^(-)?(\d+)(?:\.(\d{1,3}))?$');

  /// Accepts "2.5", "2,5", "2.500", 2.5 or 2; returns null when the value is not a quantity.
  static Quantity? tryParse(Object? value) {
    if (value == null) return null;
    if (value is int) return Quantity(value * 1000);
    if (value is double) return value.isFinite ? Quantity((value * 1000).round()) : null;
    final match = _pattern.firstMatch(value.toString().trim().replaceAll(',', '.'));
    if (match == null) return null;
    final milli = int.parse(match.group(2)!) * 1000 + int.parse((match.group(3) ?? '0').padRight(3, '0'));
    return Quantity(match.group(1) == null ? milli : -milli);
  }

  static Quantity parse(Object? value) {
    final quantity = tryParse(value);
    if (quantity == null) throw FormatException('Invalid quantity: $value');
    return quantity;
  }

  Quantity operator +(Quantity other) => Quantity(milli + other.milli);
  Quantity operator -(Quantity other) => Quantity(milli - other.milli);
  bool operator >(Quantity other) => milli > other.milli;
  bool operator <=(Quantity other) => milli <= other.milli;

  bool get isPositive => milli > 0;
  bool get isNegative => milli < 0;

  /// JSON number for request bodies (`@IsNumber({ maxDecimalPlaces: 3 })`).
  num toJson() => milli % 1000 == 0 ? milli ~/ 1000 : milli / 1000;

  /// "2.5", "12", "0.125": no trailing zeros, as people write it
  @override
  String toString() {
    final sign = milli < 0 ? '-' : '';
    final abs = milli.abs();
    final fraction = (abs % 1000).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$sign${abs ~/ 1000}${fraction.isEmpty ? '' : '.$fraction'}';
  }

  /// "+2.5" / "-0.5" for movement lists
  String get signed => milli > 0 ? '+$this' : toString();

  @override
  int compareTo(Quantity other) => milli.compareTo(other.milli);

  @override
  bool operator ==(Object other) => other is Quantity && other.milli == milli;

  @override
  int get hashCode => milli.hashCode;
}
