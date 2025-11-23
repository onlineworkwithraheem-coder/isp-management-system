import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/package.dart';
import '../widgets/custom_form_fields.dart';

// Format used across the app
final currencyFormatter = NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ');

class PackageManagementScreen extends StatefulWidget {
  const PackageManagementScreen({super.key});

  @override
  State<PackageManagementScreen> createState() => _PackageManagementScreenState();
}

class _PackageManagementScreenState extends State<PackageManagementScreen> {
  List<Package> packages = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    refreshPackages();
  }

  // Load all packages from the SQLite database
  Future refreshPackages() async {
    setState(() => isLoading = true);
    packages = await DatabaseHelper.instance.readAllPackages();
    setState(() => isLoading = false);
  }

  // Show the form to Add or Edit a package
  void _showPackageForm({Package? package}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PackageForm(package: package, onSaved: refreshPackages),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packages Management'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : packages.isEmpty
              ? Center(
                  child: Text(
                    'No packages defined yet.\nTap + to add your service packages.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final package = packages[index];
                    return _buildPackageTile(package);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPackageForm(),
        child: const Icon(Icons.add_circle_outline),
      ),
    );
  }

  Widget _buildPackageTile(Package package) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const Icon(Icons.settings_ethernet, color: Colors.indigo, size: 40),
        title: Text(
          package.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text(package.description),
        trailing: Text(
          currencyFormatter.format(package.rate),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.green),
        ),
        onTap: () => _showPackageForm(package: package),
      ),
    );
  }
}

// Package Add/Edit Form
class PackageForm extends StatefulWidget {
  final Package? package;
  final VoidCallback onSaved;
  const PackageForm({super.key, this.package, required this.onSaved});

  @override
  State<PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends State<PackageForm> {
  final _formKey = GlobalKey<FormState>();
  String? _name;
  String? _description;
  double? _rate;

  @override
  void initState() {
    super.initState();
    if (widget.package != null) {
      _name = widget.package!.name;
      _description = widget.package!.description;
      _rate = widget.package!.rate;
    }
  }

  Future _savePackage() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final isUpdating = widget.package != null;
      final package = Package(
        id: isUpdating ? widget.package!.id : null,
        name: _name!,
        description: _description!,
        rate: _rate!,
      );

      if (isUpdating) {
        await DatabaseHelper.instance.updatePackage(package);
      } else {
        await DatabaseHelper.instance.createPackage(package);
      }
      
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    }
  }
  
  Future _deletePackage() async {
    await DatabaseHelper.instance.deletePackage(widget.package!.id!);
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }


  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete package ${_name!}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deletePackage(); 
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUpdating = widget.package != null;
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
                isUpdating ? 'Edit Package Details' : 'Add New Package',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              const Divider(height: 30),
              buildCustomTextField(
                initialValue: _name,
                label: 'Package Name (e.g., Fiber 50 Mbps)',
                onSaved: (v) => _name = v,
                icon: Icons.label,
              ),
              buildCustomTextField(
                initialValue: _description,
                label: 'Description',
                onSaved: (v) => _description = v,
                icon: Icons.description,
                maxLines: 3,
              ),
              buildCustomTextField(
                initialValue: _rate?.toStringAsFixed(0),
                label: 'Monthly Rate (PKR)',
                onSaved: (v) => _rate = double.tryParse(v ?? ''),
                keyboardType: TextInputType.number,
                icon: Icons.money,
                validator: (value) {
                  if (double.tryParse(value ?? '') == null) {
                    return 'Please enter a valid rate';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (isUpdating)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showDeleteConfirmation(context),
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (isUpdating) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _savePackage,
                      icon: const Icon(Icons.save),
                      label: Text(isUpdating ? 'Update Package' : 'Save Package'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}