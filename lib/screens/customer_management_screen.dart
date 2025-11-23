import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/package.dart';
import '../widgets/custom_form_fields.dart';
import '../services/sms_service.dart'; // ADD THIS IMPORT

final currencyFormatter = NumberFormat.currency(
  locale: 'en_PK',
  symbol: 'PKR ',
);

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  List<Customer> customers = [];
  bool isLoading = false;

  // Printer (Bluetooth) state
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _bondedDevices = [];
  BluetoothDevice? _selectedPrinter;
  bool _printerConnected = false;
  String _printerStatus = 'Printer: Idle';
  final TextEditingController _printerMacController = TextEditingController(
    text: '86:67:7A:AA:20:FB',
  );

  // Progress / activity flags
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _isRefreshing = false;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  final List<String> _statusOptions = ['All', 'Paid', 'Pending', 'Due'];

  @override
  void initState() {
    super.initState();
    // Initialize bluetooth then refresh customers.
    // Auto-connect to known MAC will be attempted inside _initBluetoothDevices.
    _initBluetoothDevices().whenComplete(() {
      // run DB fetch slightly after bluetooth init to avoid UI jank
      Future.microtask(() => refreshCustomers());
    });
  }

  @override
  void dispose() {
    _printerMacController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Initialize Bluetooth bonded devices and request permissions (safe)
  Future<void> _initBluetoothDevices() async {
    try {
      // Request relevant permissions. On platforms where these perms don't exist,
      // permission_handler ignores them gracefully.
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      // Proceed even if some permissions are denied; UI will show errors later.
      final bonded = await _bluetooth.getBondedDevices();
      // isConnected may be bool or bool? depending on plugin version - normalize to bool
      final connected = (await _bluetooth.isConnected) == true;
      if (!mounted) return;
      setState(() {
        _bondedDevices = bonded;
        _printerConnected = connected;
        _printerStatus = connected ? 'Connected' : 'Idle';
      });

      // optional: listen to plugin state if available
      try {
        _bluetooth.onStateChanged().listen((s) {
          if (!mounted) return;
          setState(() => _printerStatus = 'State: $s');
        });
      } catch (_) {}

      // Auto-connect to known MAC if present and bonded device is available
      final mac = _printerMacController.text.trim();
      if (mac.isNotEmpty) {
        // try find bonded device first
        final found = _bondedDevices.firstWhere(
          (d) => (d.address ?? '').toLowerCase() == mac.toLowerCase(),
          orElse: () => BluetoothDevice('', ''), // placeholder
        );
        if ((found.address ?? '').isNotEmpty) {
          // run but don't block init
          _connectPrinter(found);
        } else {
          // If not bonded, attempt connectByMac (plugin may create device from address)
          // Keep it non-blocking and safe
          try {
            final phantom = BluetoothDevice(mac, mac);
            _connectPrinter(phantom);
          } catch (e, st) {
            debugPrint('Auto-connect phantom device failed: $e\n$st');
          }
        }
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _printerStatus = 'Init error: $e');
      debugPrint('Bluetooth init error: $e\n$st');
    }
  }

  Future<void> _connectPrinter(BluetoothDevice device) async {
    final addr = (device.address ?? '');
    if (addr.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid printer address')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _printerStatus = 'Connecting to ${device.name ?? device.address}...';
    });

    try {
      await _bluetooth.connect(device);
      final connected = (await _bluetooth.isConnected) == true;
      if (!mounted) return;
      setState(() {
        _selectedPrinter = device;
        _printerConnected = connected;
        _printerStatus = connected
            ? 'Connected: ${device.name ?? device.address}'
            : 'Not connected';
        _isConnecting = false;
      });
      debugPrint('Printer connect result: $connected for ${device.address}');
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _printerStatus = 'Connect error: $e';
        _isConnecting = false;
      });
      debugPrint('Printer connect error: $e\n$st');
      _showErrorDialog('Printer connect failed', e.toString());
    }
  }

  Future<void> _connectPrinterByMac(String mac) async {
    if (mac.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter MAC address')),
        );
      }
      return;
    }

    final found = _bondedDevices.firstWhere(
      (d) => (d.address ?? '').toLowerCase() == mac.toLowerCase(),
      // BluetoothDevice constructor requires positional args (name, address)
      orElse: () => BluetoothDevice(mac, mac),
    );
    await _connectPrinter(found);
  }

  Future<void> _disconnectPrinter() async {
    try {
      await _bluetooth.disconnect();
    } catch (e, st) {
      debugPrint('Disconnect error: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _printerConnected = false;
      _selectedPrinter = null;
      _printerStatus = 'Disconnected';
    });
  }

  // Show bottom sheet to manage printer (no separate screen)
  void _openPrinterPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_printerStatus)),
                  if (_isConnecting)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await _initBluetoothDevices();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Refreshed bonded devices'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              TextField(
                controller: _printerMacController,
                decoration: const InputDecoration(
                  labelText: 'Printer MAC (or leave to pick from list)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Connect by MAC'),
                      onPressed: () => _connectPrinterByMac(
                        _printerMacController.text.trim(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                      onPressed: _printerConnected ? _disconnectPrinter : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Bonded devices:'),
              ),
              SizedBox(
                height: 220,
                child: _bondedDevices.isEmpty
                    ? const Center(
                        child: Text(
                          'No bonded devices. Pair printer in system settings.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _bondedDevices.length,
                        itemBuilder: (context, i) {
                          final d = _bondedDevices[i];
                          final selected =
                              _selectedPrinter?.address == d.address;
                          return ListTile(
                            title: Text(d.name ?? '(no name)'),
                            subtitle: Text(d.address ?? ''),
                            trailing: selected
                                ? IconButton(
                                    icon: const Icon(Icons.link_off),
                                    onPressed: _disconnectPrinter,
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.bluetooth),
                                    onPressed: () => _connectPrinter(d),
                                  ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> refreshCustomers() async {
    // Improve responsiveness: mark refreshing and yield before DB work
    if (!mounted) return;
    setState(() {
      isLoading = customers.isEmpty; // only show full loader on first load
      _isRefreshing = true;
    });

    // yield to UI
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      // run the DB fetch; sqflite already runs on background thread internally
      final fetchedCustomers = await DatabaseHelper.instance.readAllCustomers();
      if (!mounted) return;
      setState(() {
        customers = fetchedCustomers;
        isLoading = false;
        _isRefreshing = false;
      });
      debugPrint('Loaded ${customers.length} customers');
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _isRefreshing = false;
      });
      debugPrint('Error loading customers: $e\n$st');
      _showErrorDialog('Data load failed', e.toString());
    }
  }

  // Filtered view computed from customers, search query and status filter
  List<Customer> get _filteredCustomers {
    final q = _searchQuery.trim().toLowerCase();
    return customers.where((c) {
      if (_selectedStatusFilter != 'All' &&
          c.dynamicStatus != _selectedStatusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.customerId.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();
  }

  // Show the form to Add or Edit a customer
  void _showCustomerForm({Customer? customer}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          CustomerForm(customer: customer, onSaved: refreshCustomers),
    );
  }

  // --- NEW: Bulk SMS Reminder System Logic ---
  Future<void> _checkAndSendBulkReminders() async {
    // 1. Find customers expiring tomorrow (compare date-only)
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final customersToExpireTomorrow = customers.where((customer) {
      final expiryDay = DateTime(
        customer.expiryDate.year,
        customer.expiryDate.month,
        customer.expiryDate.day,
      );
      final daysUntilExpiry = expiryDay.difference(todayDate).inDays;
      // Filter for customers expiring in 1 day (tomorrow)
      return daysUntilExpiry == 1 && customer.dynamicStatus != 'Paid';
    }).toList();

    if (customersToExpireTomorrow.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No customers found expiring tomorrow.'),
          ),
        );
      }
      return;
    }

    // 2. Prepare bulk message content
    String bulkMessageContent = '';
    int count = 0;
    List<String> phoneNumbers = [];

    for (var customer in customersToExpireTomorrow) {
      count++;
      phoneNumbers.add(customer.phone);

      final packageName =
          (await DatabaseHelper.instance.readPackageById(
            int.tryParse(customer.packageId) ?? 0,
          ))?.name ??
          'Internet Service';

      bulkMessageContent +=
          '${count}. ${customer.name} (${customer.customerId}) - Expiring tomorrow, ${DateFormat('MMM d').format(customer.expiryDate)} for ${currencyFormatter.format(customer.monthlyRate)}.\n';
    }

    // 3. Show confirmation dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Reminder to $count Customers?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following $count customers are due for renewal tomorrow:',
              ),
              const Divider(),
              Text(
                bulkMessageContent,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const Divider(),
              const Text(
                'This will open your messaging app with the reminders pre-filled.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchBulkSms(phoneNumbers);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send All Reminders'),
          ),
        ],
      ),
    );
  }
  // --- END NEW LOGIC ---

  // NEW: Automated SMS Reminders using SmsService
  Future<void> _sendAutomatedReminders() async {
    // Request SMS permissions first
    await SmsService.requestPermission();

    // Find customers expiring tomorrow (date-only compare)
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final customersToRemind = customers.where((customer) {
      final expiryDay = DateTime(
        customer.expiryDate.year,
        customer.expiryDate.month,
        customer.expiryDate.day,
      );
      final daysUntilExpiry = expiryDay.difference(todayDate).inDays;
      return daysUntilExpiry == 1 && customer.dynamicStatus != 'Paid';
    }).toList();

    if (customersToRemind.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No customers found expiring tomorrow.'),
          ),
        );
      }
      return;
    }

    // Send reminders using SmsService
    // If your SmsService supports passing recipients, update the call accordingly.
    await SmsService.sendReminders();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminders sent successfully!')),
      );
    }
  }

  // Function to launch the SMS app with multiple recipients (may not work on all devices)
  Future<void> _launchBulkSms(List<String> phoneNumbers) async {
    // Note: The ability to launch SMS to multiple recipients is heavily platform-dependent.
    // We send a generic reminder that applies to all selected users.
    final genericMessage =
        'Dear Customer, this is a reminder that your Rafiq InterNet subscription is set to expire tomorrow. Please pay to ensure uninterrupted service. Thank you, Rafiq InterNet.';

    // Try to launch with multiple recipients separated by commas (standard practice)
    final recipients = phoneNumbers.join(',');
    final uri = Uri.parse(
      'sms:$recipients?body=${Uri.encodeComponent(genericMessage)}',
    );

    final can = await canLaunchUrl(uri);
    if (can == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: Show the list of numbers to the user for manual action
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not launch bulk SMS. Please manually send to: $recipients',
            ),
          ),
        );
      }
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
          // Printer panel button (opens a bottom sheet to manage/connect printer)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Thermal Printer',
                onPressed: _openPrinterPanel,
              ),
              if (_isPrinting)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
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
          : Column(
              children: [
                if (_isRefreshing) const LinearProgressIndicator(),
                Expanded(
                  child: customers.isEmpty
                      ? Center(
                          child: Text(
                            'No customers added yet.\nTap + to add your first customer.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            // Search bar + Status filter
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon: _searchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(
                                                    () => _searchQuery = '',
                                                  );
                                                },
                                              )
                                            : null,
                                        hintText: 'Search by name, ID or phone',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 0,
                                            ),
                                      ),
                                      onChanged: (v) =>
                                          setState(() => _searchQuery = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  DropdownButton<String>(
                                    value: _selectedStatusFilter,
                                    items: _statusOptions.map((s) {
                                      return DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _selectedStatusFilter = v);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _filteredCustomers.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No customers match the current search/filter.',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: refreshCustomers,
                                      child: ListView.builder(
                                        itemCount: _filteredCustomers.length,
                                        itemBuilder: (context, index) {
                                          final customer =
                                              _filteredCustomers[index];
                                          return _buildCustomerTile(customer);
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
                ),
              ],
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
      case 'Paid':
        statusColor = Colors.green;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        break;
      case 'Due':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
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
            Text(
              'ID: ${customer.customerId} | ${customer.phone}',
              style: const TextStyle(fontSize: 12),
            ),
            FutureBuilder<Package?>(
              future: DatabaseHelper.instance.readPackageById(
                int.tryParse(customer.packageId) ?? 0,
              ),
              builder: (context, snapshot) {
                String packageName = 'Loading...';
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasData && snapshot.data != null) {
                    packageName = snapshot.data!.name;
                  } else {
                    packageName = 'Unknown';
                  }
                }
                return Text(
                  'Package: $packageName',
                  style: const TextStyle(fontSize: 12),
                );
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Expires: ${DateFormat('MMM d').format(customer.expiryDate)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        onTap: () => _showCustomerDetails(customer),
      ),
    );
  }

  void _showCustomerDetails(Customer customer) async {
    // Re-fetch package name inside the dialog for display
    final package = await DatabaseHelper.instance.readPackageById(
      int.tryParse(customer.packageId) ?? 0,
    );
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
              final oldExpiry = customer.expiryDate;
              final newExpiry = customer.expiryDate.add(
                const Duration(days: 30),
              );
              final updatedCustomer = customer.copyWith(
                status: 'Paid',
                lastPaymentDate: DateTime.now(),
                expiryDate: newExpiry,
              );
              await DatabaseHelper.instance.updateCustomer(updatedCustomer);
              if (mounted) {
                // Generate and display slip using updatedCustomer
                // Print slip should include OLD expiry (as requested)
                _showPaymentSlip(
                  context,
                  updatedCustomer,
                  amountPaid,
                  packageName,
                  oldExpiry, // pass old expiry to show on slip
                );
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
  void _showPaymentSlip(
    BuildContext context,
    Customer customer,
    double amountPaid,
    String packageName,
    DateTime oldExpiry, // now showing old expiry on slip
  ) {
    final slipContent =
        """
========================================
       RAFIQ INTERNET AND CABLES
         PAYMENT RECEIPT (80mm)
========================================
Customer: ${customer.name}
ID: ${customer.customerId}
Package: $packageName
-----------------------------------------
Amount Paid:  ${currencyFormatter.format(amountPaid)}
-----------------------------------------
Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
Expiry Date (old): ${DateFormat('MMM d, yyyy').format(oldExpiry)}
Status: PAID (Thank You!)
-----------------------------------------
Online Payments:
 Easypaisa / JazzCash: 03142190181 (Muhammad Rafiq)
Contact: Muhammad Rafiq - 03142190181
========================================
Thank you for your payment!
""";

    // Display dialog with Print/Share buttons
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Payment Slip Generated'),
          content: SingleChildScrollView(
            child: Text(
              slipContent,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                // Attempt print via connected Bluetooth thermal printer
                if (!_printerConnected || _selectedPrinter == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Printer not connected. Open printer panel to connect.',
                        ),
                      ),
                    );
                    // Open printer panel so user can connect
                    _openPrinterPanel();
                  }
                  return;
                }

                // Show printing progress dialog
                if (!mounted) return;
                setState(() => _isPrinting = true);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (pctx) {
                    return const AlertDialog(
                      content: SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  },
                );

                try {
                  // Print 80mm-friendly slip using plugin API
                  _bluetooth.printNewLine();
                  _bluetooth.printCustom('RAFIQ INTERNET AND CABLE', 3, 1);
                  _bluetooth.printNewLine();
                  _bluetooth.printCustom('PAYMENT RECEIPT', 2, 1);
                  _bluetooth.printNewLine();
                  _bluetooth.printLeftRight('Customer:', customer.name, 1);
                  _bluetooth.printLeftRight('ID:', customer.customerId, 1);
                  _bluetooth.printLeftRight('Package:', packageName, 1);
                  _bluetooth.printCustom(
                    '---------------------------------------------',
                    1,
                    0,
                  );
                  _bluetooth.printLeftRight(
                    'Amount Paid:',
                    currencyFormatter.format(amountPaid),
                    1,
                  );
                  _bluetooth.printLeftRight(
                    'Date:',
                    DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                    1,
                  );
                  _bluetooth.printLeftRight(
                    'Expiry:',
                    DateFormat('MMM d, yyyy').format(oldExpiry),
                    1,
                  );
                  _bluetooth.printNewLine();
                  _bluetooth.printCustom('Status: PAID (Thank You!)', 1, 1);
                  _bluetooth.printNewLine();
                  _bluetooth.printCustom('Online Payments:', 1, 1);
                  _bluetooth.printCustom(
                    'Easypaisa / JazzCash',
                    1,
                    1,
                  );
                  _bluetooth.printCustom('03142190181 (Muhammad Rafiq)', 1, 1);
                  _bluetooth.printNewLine();
                  _bluetooth.printCustom('For Complain: 03142190181', 1, 1);
                  _bluetooth.printNewLine();
                  try {
                    _bluetooth.paperCut();
                  } catch (_) {}
                  debugPrint('Print job sent for ${customer.customerId}');
                  // dismiss printing progress
                  if (mounted) {
                    Navigator.of(
                      context,
                    ).pop(); // close printing progress dialog
                    setState(() => _isPrinting = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Slip sent to printer')),
                    );
                  }
                } catch (e, st) {
                  debugPrint('Print failed: $e\n$st');
                  if (mounted) {
                    Navigator.of(
                      context,
                    ).pop(); // close printing progress dialog
                    setState(() => _isPrinting = false);
                    _showErrorDialog('Print failed', '$e\n$st');
                  }
                }
              },
              child: const Text('Print Slip'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Slip'),
              onPressed: () {
                Share.share(
                  slipContent,
                  subject: 'Rafiq InterNet Payment Receipt',
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  // Helper to show an error dialog and log
  void _showErrorDialog(String title, String message) {
    debugPrint('$title: $message');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
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
      if (widget.customer == null &&
          packages.isNotEmpty &&
          _selectedPackageId == null) {
        _selectedPackageId = packages.first.id.toString();
        _rate = packages.first.rate;
      }
    });
  }

  // Update rate automatically when package changes
  void _onPackageChanged(String? packageId) {
    if (packageId != null) {
      final selectedPackage = packages.firstWhere(
        (p) => p.id.toString() == packageId,
      );
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
        status: isUpdating
            ? widget.customer!.status
            : 'Pending', // New customers start as Pending
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
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
                label: Text(
                  widget.customer == null
                      ? 'Save New Customer'
                      : 'Update Customer',
                ),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Loading Packages...'),
        ),
      );
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
            child: Text(
              '${package.name} (${currencyFormatter.format(package.rate)})',
            ),
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
                date == null
                    ? 'Select Date'
                    : DateFormat('MMM d, yyyy').format(date),
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
  Widget build(BuildContext context) {
    // CONTEXT IS NOW AVAILABLE HERE
    final status = customer.dynamicStatus;
    Color statusColor;
    switch (status) {
      case 'Paid':
        statusColor = Colors.green;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        break;
      case 'Due':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
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
            _buildDetailRow(
              'Last Payment',
              DateFormat('MMM d, yyyy').format(customer.lastPaymentDate),
              Icons.date_range,
            ),
            _buildDetailRow(
              'Next Expiry',
              DateFormat('MMM d, yyyy').format(customer.expiryDate),
              Icons.calendar_today,
            ),

            const Divider(height: 30),

            // Status Update Buttons
            Row(
              children: [
                Expanded(
                  child: _buildStatusButton(
                    context,
                    'Mark Paid',
                    Colors.green,
                    Icons.check,
                    () => _showPaymentDialog(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatusButton(
                    context,
                    'SMS Remind',
                    Colors.orange,
                    Icons.message,
                    () => _sendPaymentReminder(context, customer, packageName),
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

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.indigo.shade400),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton(
    BuildContext context,
    String label,
    Color color,
    IconData icon,
    VoidCallback onPressed,
  ) {
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
              Text(
                'Customer ${customer.name} is paying ${currencyFormatter.format(monthlyRate)}.',
              ),
              const SizedBox(height: 10),
              // Use controller-backed TextField so entered amount is read correctly
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount Received (PKR)',
                  prefixIcon: const Icon(Icons.payments),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount =
                    double.tryParse(
                      amountController.text.replaceAll(',', ''),
                    ) ??
                    0.0;
                if (amount > 0) {
                  onUpdateStatus(
                    'Paid',
                    amount,
                  ); // Trigger Paid status and slip generation
                  Navigator.pop(ctx);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid amount')),
                    );
                  }
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
  void _sendPaymentReminder(
    BuildContext context,
    Customer customer,
    String packageName,
  ) async {
    final message =
        'Dear ${customer.name} (${customer.customerId}), your Rafiq InterNet package ($packageName) expires on ${DateFormat('MMM d, yyyy').format(customer.expiryDate)}. Please pay ${currencyFormatter.format(monthlyRate)} to continue uninterrupted service. Thank you, Rafiq InterNet.';
    final uri = Uri.parse(
      'sms:${customer.phone}?body=${Uri.encodeComponent(message)}',
    );

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
          content: Text(
            'Are you sure you want to delete customer ${customer.name}? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close confirmation dialog
                onDelete(); // Trigger delete action
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
