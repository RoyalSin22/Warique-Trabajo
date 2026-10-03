import '../../core/money.dart';
import '../../data/repositories.dart';
import '../../models/menu.dart';

/// Order being built by the waiter. One line per dish; the note applies to that line.
class Cart {
  final _quantities = <int, int>{};
  final _notes = <int, String>{};

  static const maxQuantity = 99; // backend: @Max(99)
  static const maxLines = 50; // backend: @ArrayMaxSize(50)

  int quantityOf(int dishId) => _quantities[dishId] ?? 0;
  String? noteOf(int dishId) => _notes[dishId];

  bool get isEmpty => _quantities.isEmpty;
  int get lineCount => _quantities.length;
  int get unitCount => _quantities.values.fold(0, (sum, quantity) => sum + quantity);
  Iterable<int> get dishIds => _quantities.keys;

  /// Returns false when the dish cannot be added (limits reached).
  bool add(int dishId) {
    final current = quantityOf(dishId);
    if (current >= maxQuantity) return false;
    if (current == 0 && lineCount >= maxLines) return false;
    _quantities[dishId] = current + 1;
    return true;
  }

  void remove(int dishId) {
    final current = quantityOf(dishId);
    if (current <= 1) {
      _quantities.remove(dishId);
      _notes.remove(dishId);
    } else {
      _quantities[dishId] = current - 1;
    }
  }

  void setNote(int dishId, String? note) {
    final trimmed = note?.trim() ?? '';
    if (trimmed.isEmpty) {
      _notes.remove(dishId);
    } else {
      _notes[dishId] = trimmed;
    }
  }

  void removeDish(int dishId) {
    _quantities.remove(dishId);
    _notes.remove(dishId);
  }

  /// Estimated total with current menu prices. The server recomputes it on creation.
  Money total(Map<int, Dish> menu) => _quantities.entries.fold(
        Money.zero,
        (sum, entry) => sum + (menu[entry.key]?.price ?? Money.zero) * entry.value,
      );

  /// Dishes in the cart that are now sold out or gone from the menu.
  List<int> unavailable(Map<int, Dish> menu) =>
      [for (final id in dishIds) if (!(menu[id]?.isAvailable ?? false)) id];

  List<NewOrderItem> toItems() => [
        for (final entry in _quantities.entries)
          NewOrderItem(dishId: entry.key, quantity: entry.value, notes: _notes[entry.key]),
      ];
}
