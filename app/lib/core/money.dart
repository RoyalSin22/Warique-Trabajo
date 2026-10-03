/// Money as integer cents, mirroring the backend (`common/utils/money.ts`).
///
/// The API returns DECIMAL values as strings ("18.50", sometimes "18.5"), so they are parsed
/// digit by digit instead of through `double`, which cannot represent most decimals exactly.
class Money implements Comparable<Money> {
  const Money(this.cents);

  final int cents;

  static const zero = Money(0);

  static final _pattern = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$');

  /// Accepts "18.50", "18.5", "18", 18.5 or 18; returns null when the value is not money.
  static Money? tryParse(Object? value) {
    if (value == null) return null;
    if (value is int) return Money(value * 100);
    if (value is double) {
      if (!value.isFinite) return null;
      return Money((value * 100).round());
    }
    final match = _pattern.firstMatch(value.toString().trim().replaceAll(',', '.'));
    if (match == null) return null;
    final whole = int.parse(match.group(2)!);
    final fraction = int.parse((match.group(3) ?? '0').padRight(2, '0'));
    final cents = whole * 100 + fraction;
    return Money(match.group(1) == null ? cents : -cents);
  }

  static Money parse(Object? value) {
    final money = tryParse(value);
    if (money == null) throw FormatException('Invalid money value: $value');
    return money;
  }

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(int factor) => Money(cents * factor);
  bool operator >(Money other) => cents > other.cents;
  bool operator <(Money other) => cents < other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  bool get isPositive => cents > 0;

  /// JSON number for request bodies (the DTOs use `@IsNumber({ maxDecimalPlaces: 2 })`).
  /// Integer cents / 100 always prints with at most two decimals in Dart.
  num toJson() => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

  /// "18.50"
  String get plain {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// "S/ 18.50", "S/ 24,397.50" (thousands separated, as receipts in Peru)
  @override
  String toString() {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = (abs ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'S/ $sign$whole.${(abs % 100).toString().padLeft(2, '0')}';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;
}
