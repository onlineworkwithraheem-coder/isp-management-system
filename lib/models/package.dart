class Package {
  final int? id; // SQLite Primary Key
  final String name;
  final String description;
  final double rate;

  Package({
    this.id,
    required this.name,
    required this.description,
    required this.rate,
  });

  // Convert Package object to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'rate': rate,
    };
  }

  // Create a Package object from a database map
  factory Package.fromMap(Map<String, dynamic> map) {
    return Package(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      rate: map['rate'],
    );
  }

  // Utility method for updating objects easily
  Package copyWith({int? id, String? name, String? description, double? rate}) {
    return Package(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rate: rate ?? this.rate,
    );
  }
}