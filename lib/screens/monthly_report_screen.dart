import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../services/backup_service.dart';

// Format used across the app
final currencyFormatter = NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ');

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  List<Customer> allCustomers = [];
  bool isLoading = true;

  // Calculated Metrics
  int totalCustomers = 0;
  int paidCustomers = 0;
  int pendingCustomers = 0;
  int dueCustomers = 0;
  double totalExpectedRevenue = 0.0;
  
  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  // Loads data and calculates all metrics
  Future _loadReports() async {
    setState(() => isLoading = true);
    
    final fetchedCustomers = await DatabaseHelper.instance.readAllCustomers();
    
    // Reset metrics
    totalCustomers = fetchedCustomers.length;
    paidCustomers = 0;
    pendingCustomers = 0;
    dueCustomers = 0;
    totalExpectedRevenue = 0.0;
    
    for (var customer in fetchedCustomers) {
      final status = customer.dynamicStatus;
      totalExpectedRevenue += customer.monthlyRate;
      
      switch (status) {
        case 'Paid':
          paidCustomers++;
          break;
        case 'Pending':
          pendingCustomers++;
          break;
        case 'Due':
          dueCustomers++;
          break;
      }
    }
    
    setState(() {
      allCustomers = fetchedCustomers;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Progress Report'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : _loadReports,
            tooltip: 'Refresh Report',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Text(
                    'Metrics Overview (${DateFormat('MMMM yyyy').format(DateTime.now())})',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo), // Using base color
                  ),
                  const Divider(),
                  _buildMetricsGrid(context),
                  const SizedBox(height: 20),
                  
                  Text(
                    'Customer Status Breakdown ($totalCustomers Total)',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo), // Using base color
                  ),
                  const Divider(),
                  _buildStatusList('Paid Customers ($paidCustomers)', Colors.green, 'Paid'),
                  _buildStatusList('Pending Reminders ($pendingCustomers)', Colors.orange, 'Pending'),
                  _buildStatusList('Due Payments ($dueCustomers)', Colors.red, 'Due'),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'export',
            backgroundColor: Colors.indigo,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Export Backup'),
            onPressed: () async {
              await BackupService.exportBackup();
            },
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'import',
            backgroundColor: Colors.green,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Import Backup'),
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(type: FileType.any);
              if (result != null) {
                final file = File(result.files.single.path!);
                await BackupService.importBackup(file);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Backup restored successfully!')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
  
  // Widget for the top metrics grid
  Widget _buildMetricsGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricCard(
          'Total Customers', 
          totalCustomers.toString(), 
          Icons.people_alt, 
          Colors.indigo,
        ),
        _buildMetricCard(
          'Expected Revenue', 
          currencyFormatter.format(totalExpectedRevenue), 
          Icons.account_balance_wallet, 
          Colors.teal,
        ),
        _buildMetricCard(
          'Paid This Month', 
          paidCustomers.toString(), 
          Icons.check_circle, 
          Colors.green,
        ),
        _buildMetricCard(
          'Payment Due', 
          dueCustomers.toString(), 
          Icons.warning_rounded, 
          Colors.red,
        ),
      ],
    );
  }
  
  // Custom card for metrics
  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold, 
                color: color, // FIXED: Using base color instead of shade700
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Collapsible list for customer status breakdown
  Widget _buildStatusList(String header, Color color, String statusFilter) {
    final filteredCustomers = allCustomers.where((c) => c.dynamicStatus == statusFilter).toList();
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          header,
          style: TextStyle(fontWeight: FontWeight.bold, color: color), // FIXED: Using base color instead of shade800
        ),
        leading: Icon(Icons.list, color: color),
        children: filteredCustomers.map((customer) => ListTile(
          dense: true,
          title: Text(customer.name),
          subtitle: Text(
            'Expires: ${DateFormat('MMM d, yyyy').format(customer.expiryDate)} | Rate: ${currencyFormatter.format(customer.monthlyRate)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(customer.customerId),
        )).toList(),
      ),
    );
  }
}