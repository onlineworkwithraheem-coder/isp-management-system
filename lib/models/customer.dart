import 'package:intl/intl.dart';

final dateFormatter = DateFormat('MMM d, yyyy');

class Customer {
  final int? id; // SQLite Primary Key
  final String customerId; // Your business-specific ID (C1001)
  final String name;
  final String phone;
  final String address;
  final String packageId; // ID of the linked Package (as String)
  final double monthlyRate;
  final String status; // Paid, Pending, Due
  final DateTime expiryDate;
  final DateTime lastPaymentDate;

  Customer({
    this.id,
    required this.customerId,
    required this.name,
    required this.phone,
    required this.address,
    required this.packageId,
    required this.monthlyRate,
    required this.status,
    required this.expiryDate,
    required this.lastPaymentDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'name': name,
      'phone': phone,
      'address': address,
      'packageId': packageId,
      'monthlyRate': monthlyRate,
      'status': status,
      'expiryDate': expiryDate.toIso8601String(), // Store dates as strings
      'lastPaymentDate': lastPaymentDate.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      customerId: map['customerId'],
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      packageId: map['packageId'],
      monthlyRate: map['monthlyRate'],
      status: map['status'],
      expiryDate: DateTime.parse(map['expiryDate']),
      lastPaymentDate: DateTime.parse(map['lastPaymentDate']),
    );
  }
  
  // Custom getter to calculate status based on date (Dynamic Data)
  String get dynamicStatus {
    final now = DateTime.now();
    final oneDayBeforeExpiry = expiryDate.subtract(const Duration(days: 1));

    if (status == 'Paid' && expiryDate.isAfter(now)) return 'Paid';
    if (expiryDate.isBefore(now)) return 'Due';
    if (now.isAfter(oneDayBeforeExpiry)) return 'Pending';
    
    return 'Pending';
  }

  // Utility method for updating objects easily
  Customer copyWith({
    int? id, String? customerId, String? name, String? phone, String? address,
    String? packageId, double? monthlyRate, String? status, 
    DateTime? expiryDate, DateTime? lastPaymentDate,
  }) {
    return Customer(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      packageId: packageId ?? this.packageId,
      monthlyRate: monthlyRate ?? this.monthlyRate,
      status: status ?? this.status,
      expiryDate: expiryDate ?? this.expiryDate,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
    );
  }
}