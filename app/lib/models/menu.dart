import '../core/money.dart';

class CategoryRef {
  const CategoryRef({required this.id, required this.name});

  factory CategoryRef.fromJson(Map<String, dynamic> json) =>
      CategoryRef(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;
}

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.isAvailable,
    required this.isActive,
    this.description,
  });

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: Money.parse(json['price']),
        category: CategoryRef.fromJson(json['category'] as Map<String, dynamic>),
        isAvailable: json['isAvailable'] as bool,
        isActive: json['isActive'] as bool? ?? true,
      );

  final int id;
  final String name;
  final String? description;
  final Money price;
  final CategoryRef category;

  /// false = "agotado hoy" (kitchen or owner toggles it).
  final bool isAvailable;

  /// false = removed from the menu (soft delete).
  final bool isActive;

  Dish copyWith({bool? isAvailable}) => Dish(
        id: id,
        name: name,
        description: description,
        price: price,
        category: category,
        isAvailable: isAvailable ?? this.isAvailable,
        isActive: isActive,
      );
}

class DiningTable {
  const DiningTable({required this.id, required this.label});

  factory DiningTable.fromJson(Map<String, dynamic> json) =>
      DiningTable(id: json['id'] as int, label: json['label'] as String);

  final int id;
  final String label;
}
