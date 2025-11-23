import 'package:telephony/telephony.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';

class SmsService {
  static final Telephony telephony = Telephony.instance;

  /// Request permission to send SMS
  static Future<void> requestPermission() async {
    await telephony.requestSmsPermissions ?? await telephony.requestPhoneAndSmsPermissions;
  }

  /// Send reminder SMS for customers expiring tomorrow
  static Future<void> sendReminders() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> result = await db.query('customers');

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    for (var map in result) {
      final customer = Customer.fromMap(map);
      final expiry = customer.expiryDate;

      if (expiry.year == tomorrow.year &&
          expiry.month == tomorrow.month &&
          expiry.day == tomorrow.day) {
        final message =
            'Dear ${customer.name}, we would like to remind you that the amount ${customer.monthlyRate.toStringAsFixed(0)} was due for payment. To avoid service interruption, please forward the payment. Regards, RAFIQ NET';

        try {
          await telephony.sendSms(
            to: customer.phone,
            message: message,
          );
          print('✅ SMS sent to ${customer.name}');
        } catch (e) {
          print('❌ Failed to send SMS to ${customer.name}: $e');
        }
      }
    }
  }
}
