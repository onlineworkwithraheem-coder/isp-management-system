import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/package.dart';
import '../widgets/custom_form_fields.dart';
import '../services/sms_service.dart'; // ADD THIS IMPORT

final currencyFormatter = NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ');

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  List<Customer> customers = [];
  bool isLoading = false;
  
  @override
  void initState() {
    super.initState();
    refreshCustomers();
  }

  Future refreshCustomers() async {
    setState(() => isLoading = true);
    final fetchedCustomers = await DatabaseHelper.instance.readAllCustomers();
    setState(() {
      customers = fetchedCustomers;
      isLoading = false;
    });
  }

  // Show the form to Add or Edit a customer
  void _showCustomerForm({Customer? customer}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CustomerForm(customer: customer, onSaved: refreshCustomers),
    );
  }

  // --- NEW: Bulk SMS Reminder System Logic ---
  Future<void> _checkAndSendBulkReminders() async {
    // 1. Find customers expiring tomorrow
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final customersToExpireTomorrow = customers.where((customer) {
      final expiryDay = DateTime(customer.expiryDate.year, customer.expiryDate.month, customer.expiryDate.day);
      final daysUntilExpiry = expiryDay.difference(now).inDays;
      // Filter for customers expiring in 1 day (tomorrow)
      return daysUntilExpiry == 1 && customer.dynamicStatus != 'Paid';
    }).toList();

    if (customersToExpireTomorrow.isEmpty) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customers found expiring tomorrow.')),
      );
      return;
    }

    // 2. Prepare bulk message content
    String bulkMessageContent = '';
    int count = 0;
    List<String> phoneNumbers = [];

    for (var customer in customersToExpireTomorrow) {
      count++;
      phoneNumbers.add(customer.phone);
      
      final packageName = (await DatabaseHelper.instance.readPackageById(int.tryParse(customer.packageId) ?? 0))?.name ?? 'Internet Service';
      
      bulkMessageContent += 
        '${count}. ${customer.name} (${customer.customerId}) - Expiring tomorrow, ${DateFormat('MMM d').format(customer.expiryDate)} for ${currencyFormatter.format(customer.monthlyRate)}.\n';
    }
    
    // 3. Show confirmation dialog
    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Reminder to $count Customers?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The following ${count} customers are due for renewal tomorrow:'),
              const Divider(),
              Text(bulkMessageContent, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              const Divider(),
              const Text('This will open your messaging app with the reminders pre-filled.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchBulkSms(phoneNumbers);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Send All Reminders'),
          ),
        ],
      ),
    );
  }

  // NEW: Automated SMS Reminders using SmsService
  Future<void> _sendAutomatedReminders() async {
    // Request SMS permissions first
    await SmsService.requestPermission();
    
    // Find customers expiring tomorrow
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final customersToRemind = customers.where((customer) {
      final expiryDay = DateTime(customer.expiryDate.year, customer.expiryDate.month, customer.expiryDate.day);
      final daysUntilExpiry = expiryDay.difference(now).inDays;
      return daysUntilExpiry == 1 && customer.dynamicStatus != 'Paid';
    }).toList();

    if (customersToRemind.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No customers found expiring tomorrow.')),
        );
      }
      return;
    }

    // Send reminders using SmsService
    await SmsService.sendReminders();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminders sent successfully!')),
      );
    }
  }

  // Function to launch the SMS app with multiple recipients (may not work on all devices)
  void _launchBulkSms(List<String> phoneNumbers) async {
    // Note: The ability to launch SMS to multiple recipients is heavily platform-dependent.
    // We send a generic reminder that applies to all selected users.
    final genericMessage = 'Dear Customer, this is a reminder that your Rafiq InterNet subscription is set to expire tomorrow. Please pay to ensure uninterrupted service. Thank you, Rafiq InterNet.';
    
    // Try to launch with multiple recipients separated by commas (standard practice)
    final recipients = phoneNumbers.join(',');
    final uri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(genericMessage)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: Show the list of numbers to the user for manual action
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch bulk SMS. Please manually send to: $recipients')),
      );
    }
  }
  // --- END NEW LOGIC ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers Management'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // NEW: Automated Reminder Button using SmsService
          IconButton(
            icon: const Icon(Icons.send_and_archive),
            tooltip: 'Send Automated Reminders',
            onPressed: isLoading ? null : _sendAutomatedReminders,
          ),
          // Existing bulk reminder button
          IconButton(
            icon: const Icon(Icons.send_rounded),
            tooltip: 'Bulk Reminder (Expires Tomorrow)',
            onPressed: isLoading ? null : _checkAndSendBulkReminders,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : customers.isEmpty
              ? Center(
                  child: Text(
                    'No customers added yet.\nTap + to add your first customer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  itemCount: customers.length,
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return _buildCustomerTile(customer);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerForm(),
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Widget _buildCustomerTile(Customer customer) {
    final status = customer.dynamicStatus;
    Color statusColor;
    switch (status) {
      case 'Paid': statusColor = Colors.green; break;
      case 'Pending': statusColor = Colors.orange; break;
      case 'Due': statusColor = Colors.red; break;
      default: statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: statusColor.withAlpha(25), 
          child: Icon(Icons.person, color: statusColor),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${customer.customerId} | ${customer.phone}', style: const TextStyle(fontSize: 12)),
            FutureBuilder<Package?>(
              future: DatabaseHelper.instance.readPackageById(int.tryParse(customer.packageId) ?? 0),
              builder: (context, snapshot) {
                String packageName = 'Loading...';
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  packageName = snapshot.data!.name;
                }
                return Text('Package: $packageName', style: const TextStyle(fontSize: 12));
              },
            ),
          ],
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Expires: ${DateFormat('MMM d').format(customer.expiryDate)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        onTap: () => _showCustomerDetails(customer),
      ),
    );
  }

  void _showCustomerDetails(Customer customer) async {
    // Re-fetch package name inside the dialog for display
    final package = await DatabaseHelper.instance.readPackageById(int.tryParse(customer.packageId) ?? 0);
    final packageName = package?.name ?? 'Unknown';
    final monthlyRate = package?.rate ?? customer.monthlyRate;

    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return CustomerDetailDialog(
          customer: customer,
          packageName: packageName,
          monthlyRate: monthlyRate,
          onDelete: () async {
            await DatabaseHelper.instance.deleteCustomer(customer.id!);
            if (mounted) {
              Navigator.pop(context); // Close details dialog
              refreshCustomers();
            }
          },
          onEdit: () {
            Navigator.pop(context); // Close details dialog
            _showCustomerForm(customer: customer);
          },
          onUpdateStatus: (newStatus, amountPaid) async {
            // Handle payment status update
            if (newStatus == 'Paid') {
              final newExpiry = customer.expiryDate.add(const Duration(days: 30));
              final updatedCustomer = customer.copyWith(
                status: 'Paid',
                lastPaymentDate: DateTime.now(),
                expiryDate: newExpiry,
              );
              await DatabaseHelper.instance.updateCustomer(updatedCustomer);
              if (mounted) {
                // Generate and display slip
                _showPaymentSlip(context, customer, amountPaid, packageName, newExpiry);
                refreshCustomers();
              }
            } else {
              final updatedCustomer = customer.copyWith(status: newStatus);
               await DatabaseHelper.instance.updateCustomer(updatedCustomer);
               refreshCustomers();
            }
          },
        );
      },
    );
  }
  
  // Payment Slip Generation & Share Logic
  void _showPaymentSlip(BuildContext context, Customer customer, double amountPaid, String packageName, DateTime newExpiry) {
    final slipContent = """
========================================
       RAFIQ INTERNET PAYMENT SLIP
========================================
Customer: ${customer.name}
ID: ${customer.customerId}
Package: $packageName
----------------------------------------
Amount Paid:  ${currencyFormatter.format(amountPaid)}
----------------------------------------
Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
New Expiry: ${DateFormat('MMM d, yyyy').format(newExpiry)}
Status: PAID (Thank You!)
========================================
For support, contact 03XX-XXXXXXX
""";
    
    // Display dialog with Print/Share buttons
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Payment Slip Generated'),
          content: SingleChildScrollView(
            child: Text(slipContent, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Placeholder for mini printer integration (Bluetooth/USB)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mini Printer not connected. Slip copied.')),
                );
                // In a real app, this would initiate a Bluetooth print job
                Navigator.pop(ctx);
              },
              child: const Text('Print Slip'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Slip'),
              onPressed: () {
                Share.share(slipContent, subject: 'Rafiq InterNet Payment Receipt');
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}

// ... REST OF THE CODE REMAINS THE SAME (CustomerForm and CustomerDetailDialog classes)
// [The rest of your CustomerForm and CustomerDetailDialog classes remain unchanged]

// ---------------------- CUSTOMER FORM ----------------------

class CustomerForm extends StatefulWidget {
  final Customer? customer;
  final VoidCallback onSaved;
  const CustomerForm({super.key, this.customer, required this.onSaved});

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  
  String? _customerId;
  String? _name;
  String? _phone;
  String? _address;
  String? _selectedPackageId;
  double? _rate;
  DateTime? _expiryDate;
  DateTime _lastPaymentDate = DateTime.now().subtract(const Duration(days: 30));

  List<Package> packages = [];
  bool isLoadingPackages = true;

  @override
  void initState() {
    super.initState();
    _loadPackages();
    if (widget.customer != null) {
      _customerId = widget.customer!.customerId;
      _name = widget.customer!.name;
      _phone = widget.customer!.phone;
      _address = widget.customer!.address;
      _selectedPackageId = widget.customer!.packageId;
      _rate = widget.customer!.monthlyRate;
      _expiryDate = widget.customer!.expiryDate;
      _lastPaymentDate = widget.customer!.lastPaymentDate;
    } else {
      // Set default expiry to next month if creating a new customer
      _expiryDate = DateTime.now().add(const Duration(days: 30));
    }
  }

  Future _loadPackages() async {
    final fetchedPackages = await DatabaseHelper.instance.readAllPackages();
    setState(() {
      packages = fetchedPackages;
      isLoadingPackages = false;
      // Set default package if adding new customer and packages exist
      if (widget.customer == null && packages.isNotEmpty && _selectedPackageId == null) {
        _selectedPackageId = packages.first.id.toString();
        _rate = packages.first.rate;
      }
    });
  }
  
  // Update rate automatically when package changes
  void _onPackageChanged(String? packageId) {
    if (packageId != null) {
      final selectedPackage = packages.firstWhere((p) => p.id.toString() == packageId);
      setState(() {
        _selectedPackageId = packageId;
        _rate = selectedPackage.rate;
      });
    }
  }

  Future _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final isUpdating = widget.customer != null;
      final customer = Customer(
        id: isUpdating ? widget.customer!.id : null,
        customerId: _customerId!,
        name: _name!,
        phone: _phone!,
        address: _address!,
        packageId: _selectedPackageId!,
        monthlyRate: _rate!,
        status: isUpdating ? widget.customer!.status : 'Pending', // New customers start as Pending
        expiryDate: _expiryDate!,
        lastPaymentDate: _lastPaymentDate,
      );

      if (isUpdating) {
        await DatabaseHelper.instance.updateCustomer(customer);
      } else {
        await DatabaseHelper.instance.createCustomer(customer);
      }
      
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.customer == null ? 'Add New Customer' : 'Edit Customer',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              const Divider(height: 30),
              
              buildCustomTextField(
                initialValue: _customerId,
                label: 'Customer ID (e.g., C1001)',
                onSaved: (v) => _customerId = v,
                icon: Icons.vpn_key,
              ),
              buildCustomTextField(
                initialValue: _name,
                label: 'Full Name',
                onSaved: (v) => _name = v,
                icon: Icons.person,
              ),
              buildCustomTextField(
                initialValue: _phone,
                label: 'Contact Number',
                onSaved: (v) => _phone = v,
                keyboardType: TextInputType.phone,
                icon: Icons.phone,
              ),
              buildCustomTextField(
                initialValue: _address,
                label: 'Street/Full Address',
                onSaved: (v) => _address = v,
                icon: Icons.location_on,
              ),
              
              // Package Dropdown
              _buildPackageDropdown(),
              
              // Monthly Rate (Read-only, updated by package dropdown)
              buildCustomTextField(
                initialValue: _rate?.toStringAsFixed(0),
                label: 'Monthly Rate (PKR) - Auto-filled',
                readOnly: true,
                onSaved: (v) {},
                icon: Icons.money,
                validator: (_) => null, // 👈 disables validation for this field
              ),
              
              // Expiry Date Picker
              _buildDateRow(
                context,
                'Subscription Expiry Date',
                _expiryDate,
                (date) => setState(() => _expiryDate = date),
              ),
              
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saveCustomer,
                icon: const Icon(Icons.save),
                label: Text(widget.customer == null ? 'Save New Customer' : 'Update Customer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPackageDropdown() {
    if (isLoadingPackages) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Loading Packages...')));
    }
    
    if (packages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'No packages found. Please add packages first in the Packages Management tab.',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: _selectedPackageId,
        decoration: InputDecoration(
          labelText: 'Select Package',
          prefixIcon: Icon(Icons.wifi, color: Colors.indigo.shade400),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: packages.map((package) {
          return DropdownMenuItem<String>(
            value: package.id.toString(),
            child: Text('${package.name} (${currencyFormatter.format(package.rate)})'),
          );
        }).toList(),
        onChanged: _onPackageChanged,
        validator: (value) => value == null ? 'Please select a package' : null,
      ),
    );
  }
  
  Widget _buildDateRow(
    BuildContext context,
    String label,
    DateTime? date,
    Function(DateTime) onDateSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded( 
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded( 
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(
                          primary: Colors.indigo,
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (pickedDate != null) {
                  onDateSelected(pickedDate);
                }
              },
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                date == null ? 'Select Date' : DateFormat('MMM d, yyyy').format(date),
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------- CUSTOMER DETAILS DIALOG ----------------------

class CustomerDetailDialog extends StatelessWidget {
  final Customer customer;
  final String packageName;
  final double monthlyRate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Function(String newStatus, double amountPaid) onUpdateStatus;

  const CustomerDetailDialog({
    super.key,
    required this.customer,
    required this.packageName,
    required this.monthlyRate,
    required this.onDelete,
    required this.onEdit,
    required this.onUpdateStatus,
  });

  @override
  Widget build(BuildContext context) { // CONTEXT IS NOW AVAILABLE HERE
    final status = customer.dynamicStatus;
    Color statusColor;
    switch (status) {
      case 'Paid': statusColor = Colors.green; break;
      case 'Pending': statusColor = Colors.orange; break;
      case 'Due': statusColor = Colors.red; break;
      default: statusColor = Colors.grey;
    }
    
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                '${customer.name} Details',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
            const Divider(height: 30),
            _buildDetailRow('Customer ID', customer.customerId, Icons.vpn_key),
            _buildDetailRow('Phone', customer.phone, Icons.phone),
            _buildDetailRow('Address', customer.address, Icons.location_on),
            _buildDetailRow('Package', packageName, Icons.wifi),
            _buildDetailRow(
              'Monthly Rate',
              currencyFormatter.format(monthlyRate),
              Icons.money_rounded,
            ),
            _buildDetailRow('Status', status, Icons.info, color: statusColor),
            _buildDetailRow('Last Payment', DateFormat('MMM d, yyyy').format(customer.lastPaymentDate), Icons.date_range),
            _buildDetailRow('Next Expiry', DateFormat('MMM d, yyyy').format(customer.expiryDate), Icons.calendar_today),
            
            const Divider(height: 30),
            
            // Status Update Buttons
            Row(
              children: [
                Expanded(
                  child: _buildStatusButton(
                    context, 'Mark Paid', Colors.green, Icons.check, () => _showPaymentDialog(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatusButton(
                    context, 'SMS Remind', Colors.orange, Icons.message, () => _sendPaymentReminder(context, customer, packageName),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade100,
                      foregroundColor: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showDeleteConfirmation(context, onDelete),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.indigo.shade400),
          const SizedBox(width: 10),
          SizedBox(
            width: 100, 
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color ?? Colors.black87, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton(BuildContext context, String label, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
  
  void _showPaymentDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController(
      text: monthlyRate.toStringAsFixed(0),
    );
    
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Receive Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Customer ${customer.name} is paying ${currencyFormatter.format(monthlyRate)}.'),
              const SizedBox(height: 10),
              buildCustomTextField(
                initialValue: amountController.text,
                label: 'Amount Received (PKR)',
                onSaved: (v) {}, // Unused, reading from controller
                keyboardType: TextInputType.number,
                icon: Icons.payments,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount > 0) {
                  onUpdateStatus('Paid', amount); // Trigger Paid status and slip generation
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Confirm Payment'),
            ),
          ],
        );
      },
    );
  }

  // Individual SMS Reminder Function
  void _sendPaymentReminder(BuildContext context, Customer customer, String packageName) async {
    final message = 'Dear ${customer.name} (${customer.customerId}), your Rafiq InterNet package ($packageName) expires on ${DateFormat('MMM d, yyyy').format(customer.expiryDate)}. Please pay ${currencyFormatter.format(monthlyRate)} to continue uninterrupted service. Thank you, Rafiq InterNet.';
    final uri = Uri.parse('sms:${customer.phone}?body=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // context is now available to show the SnackBar
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch SMS app.')),
      );
    }
  }

  void _showDeleteConfirmation(BuildContext context, VoidCallback onDelete) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete customer ${customer.name}? This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close confirmation dialog
                onDelete(); // Trigger delete action
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}