enum Role {
  owner('OWNER', 'Dueño'),
  waiter('WAITER', 'Mozo'),
  kitchen('KITCHEN', 'Cocina');

  const Role(this.api, this.label);

  final String api;
  final String label;

  static Role fromApi(String value) =>
      values.firstWhere((role) => role.api == value, orElse: () => throw FormatException(value));
}

class AppUser {
  const AppUser({required this.id, required this.username, required this.fullName, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        role: Role.fromApi(json['role'] as String),
      );

  final int id;
  final String username;
  final String fullName;
  final Role role;
}
