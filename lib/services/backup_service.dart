import 'dart:io';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/database_helper.dart';

class BackupService {
  /// Export and email JSON backup file
  static Future<void> exportBackup() async {
    final db = await DatabaseHelper.instance.database;

    final customers = await db.query('customers');
    final packages = await db.query('packages');

    final backupData = {
      'customers': customers,
      'packages': packages,
    };

    final jsonString = jsonEncode(backupData);

    final directory = await getApplicationDocumentsDirectory();
    final filePath = join(directory.path, 'isp_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    final file = File(filePath);
    await file.writeAsString(jsonString);

    // ✅ Step 1: Create mailto link
    final subject = Uri.encodeComponent('Rafiq Internet Backup');
    final body = Uri.encodeComponent('Attached is the latest backup from Rafiq Internet Admin App.');
    final email = Uri.encodeComponent('rafiqinternetbackup@gmail.com'); // 🟡 Change this to your Gmail address

    final mailtoUrl = Uri.parse('mailto:$email?subject=$subject&body=$body');

    // ✅ Step 2: Try opening Gmail first, else share file manually
    if (await canLaunchUrl(mailtoUrl)) {
      await launchUrl(mailtoUrl);
      await Share.shareXFiles([XFile(file.path)], text: 'Backup File from Rafiq Internet');
    } else {
      await Share.shareXFiles([XFile(file.path)], text: 'Rafiq Internet Backup File');
    }
  }

  /// Import backup from JSON file
  static Future<void> importBackup(File file) async {
    final db = await DatabaseHelper.instance.database;
    final content = await file.readAsString();
    final data = jsonDecode(content);

    final customers = List<Map<String, dynamic>>.from(data['customers']);
    final packages = List<Map<String, dynamic>>.from(data['packages']);

    await db.transaction((txn) async {
      await txn.delete('customers');
      await txn.delete('packages');

      for (var pkg in packages) {
        await txn.insert('packages', pkg);
      }

      for (var cust in customers) {
        await txn.insert('customers', cust);
      }
    });

    print("✅ Backup restored successfully. Customers: ${customers.length}, Packages: ${packages.length}");
  }
}