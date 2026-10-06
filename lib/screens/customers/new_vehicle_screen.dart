import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/vehicle_options.dart';
import '../../services/briskers_api.dart';
import 'vin_scanner_screen.dart';

class NewVehicleScreen extends StatefulWidget {
  const NewVehicleScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    this.vehicle,
  });

  final String businessId;
  final String customerId;
  final Map<String, dynamic>? vehicle;

  bool get isEditing => vehicle != null;

  @override
  State<NewVehicleScreen> createState() => _NewVehicleScreenState();
}

class _NewVehicleScreenState extends State<NewVehicleScreen> {
  static const _api = BriskersApi();

  final _year = TextEditingController();
  final _model = TextEditingController();
  final _vin = TextEditingController();
  final _plate = TextEditingController();
  final _mileage = TextEditingController();
  final _color = TextEditingController();
  final _keyPassword = TextEditingController();

  String? _make;
  String? _licenseState;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    if (vehicle != null) {
      _year.text = vehicle['year']?.toString() ?? '';
      _model.text = vehicle['model']?.toString() ?? '';
      _vin.text = vehicle['vin']?.toString() ?? '';
      _plate.text = vehicle['license_plate']?.toString() ?? '';
      _mileage.text = vehicle['mileage']?.toString() ?? '';
      _color.text = vehicle['color']?.toString() ?? '';
      _keyPassword.text = vehicle['key_password']?.toString() ?? '';

      final existingMake = vehicle['make']?.toString();
      if (existingMake != null && existingMake.isNotEmpty) {
        _make = vehicleMakes.contains(existingMake) ? existingMake : null;
      }

      final existingState = vehicle['license_state']?.toString();
      if (existingState != null && usStateCodes.contains(existingState)) {
        _licenseState = existingState;
      }
    }
  }

  @override
  void dispose() {
    _year.dispose();
    _model.dispose();
    _vin.dispose();
    _plate.dispose();
    _mileage.dispose();
    _color.dispose();
    _keyPassword.dispose();
    super.dispose();
  }

  Future<void> _scanVin() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VinScannerScreen()),
    );
    if (value == null || !mounted) return;
    _vin.text = value;
    _vin.selection = TextSelection.collapsed(offset: _vin.text.length);
  }

  Future<void> _save() async {
    final make = _make;
    final model = _model.text.trim();

    if (make == null || model.isEmpty) {
      setState(() => _error = 'Make and model are required.');
      return;
    }

    final year = _year.text.trim().isEmpty
        ? null
        : int.tryParse(_year.text.trim());
    if (_year.text.trim().isNotEmpty && year == null) {
      setState(() => _error = 'Enter a valid vehicle year.');
      return;
    }

    final mileage = _mileage.text.trim().isEmpty
        ? null
        : num.tryParse(_mileage.text.replaceAll(',', '').trim());
    if (_mileage.text.trim().isNotEmpty && mileage == null) {
      setState(() => _error = 'Enter valid mileage.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final params = (
        make: make,
        model: model,
        year: year,
        vin: _vin.text.trim().isEmpty ? null : normalizeVin(_vin.text),
        licensePlate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        licenseState: _licenseState,
        mileage: mileage,
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        keyPassword: _keyPassword.text.trim().isEmpty
            ? null
            : _keyPassword.text.trim(),
      );

      if (widget.isEditing) {
        await _api.updateVehicle(
          widget.businessId,
          widget.vehicle!['id'].toString(),
          make: params.make,
          model: params.model,
          year: params.year,
          vin: params.vin,
          licensePlate: params.licensePlate,
          licenseState: params.licenseState,
          mileage: params.mileage,
          color: params.color,
          keyPassword: params.keyPassword,
        );
      } else {
        await _api.createVehicle(
          widget.businessId,
          widget.customerId,
          make: params.make,
          model: params.model,
          year: params.year,
          vin: params.vin,
          licensePlate: params.licensePlate,
          licenseState: params.licenseState,
          mileage: params.mileage,
          color: params.color,
          keyPassword: params.keyPassword,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit vehicle' : 'Add vehicle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(labelText: 'Year'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _make,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Make *'),
                  items: vehicleMakes
                      .map(
                        (make) => DropdownMenuItem(
                          value: make,
                          child: Text(make),
                        ),
                      )
                      .toList(),
                  onChanged: _busy ? null : (value) => setState(() => _make = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Model *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vin,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            inputFormatters: const [VinTextInputFormatter()],
            decoration: InputDecoration(
              labelText: 'VIN',
              helperText: 'Scan it or type/edit it manually',
              suffixIcon: IconButton(
                onPressed: _scanVin,
                tooltip: 'Scan VIN barcode',
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'License plate'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _licenseState,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'State issued'),
                  items: usStateCodes
                      .map(
                        (state) => DropdownMenuItem(
                          value: state,
                          child: Text(state),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _licenseState = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mileage,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Mileage',
              suffixText: 'mi',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _color,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Color'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyPassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Key Password / Key Code',
              helperText: 'Internal shop information only',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(widget.isEditing ? 'Save changes' : 'Save vehicle'),
          ),
        ],
      ),
    );
  }
}
