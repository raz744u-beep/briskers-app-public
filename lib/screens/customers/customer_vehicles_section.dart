import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';

class CustomerVehiclesSection extends StatelessWidget {
  const CustomerVehiclesSection({
    super.key,
    required this.vehicles,
    required this.onAdd,
    required this.onEdit,
    this.enabled = true,
  });

  final List<dynamic> vehicles;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;

  String _vehicleName(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) '${vehicle['year']}',
      '${vehicle['make'] ?? ''}'.trim(),
      '${vehicle['model'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vehicles',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add, color: BriskersColors.vehicles),
              label: const Text('Vehicle'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (vehicles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No vehicles yet.'),
            ),
          )
        else
          ...vehicles.map((row) {
            final vehicle = Map<String, dynamic>.from(row as Map);
            final plate = '${vehicle['license_plate'] ?? ''}'.trim();
            final state = '${vehicle['license_state'] ?? ''}'.trim();
            final vin = '${vehicle['vin'] ?? ''}'.trim();
            final color = '${vehicle['color'] ?? ''}'.trim();
            final keyPassword =
                '${vehicle['key_password'] ?? ''}'.trim();
            final mileage = vehicle['mileage'];

            return Card(
              child: ExpansionTile(
                initiallyExpanded: false,
                maintainState: false,
                leading: const Icon(
                  Icons.directions_car_outlined,
                  color: BriskersColors.vehicles,
                ),
                title: Text(
                  _vehicleName(vehicle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (plate.isNotEmpty)
                          _detailRow(
                            context,
                            'Plate',
                            state.isEmpty ? plate : '$plate ($state)',
                          ),
                        if (mileage != null)
                          _detailRow(context, 'Mileage', '$mileage mi'),
                        if (vin.isNotEmpty)
                          _detailRow(context, 'VIN', vin),
                        if (color.isNotEmpty)
                          _detailRow(context, 'Color', color),
                        if (keyPassword.isNotEmpty)
                          _detailRow(
                            context,
                            'Key Code',
                            keyPassword,
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed:
                                enabled ? () => onEdit(vehicle) : null,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: BriskersColors.vehicles,
                            ),
                            label: const Text('Edit vehicle'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
