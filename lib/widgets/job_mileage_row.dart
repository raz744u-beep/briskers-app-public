import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compact, fixed-footprint mileage overview beneath the vehicle's VIN.
/// Unknown readings remain unknown; only independently verified snapshots
/// should populate these values.
class JobMileageRow extends StatelessWidget {
  const JobMileageRow({
    super.key,
    required this.mileageIn,
    required this.mileageOut,
    this.onEditIn,
    this.onOpenOut,
  });

  final num? mileageIn;
  final num? mileageOut;
  final VoidCallback? onEditIn;
  final VoidCallback? onOpenOut;

  String _text(num? reading) => reading == null
      ? '—'
      : NumberFormat.decimalPattern('en_US').format(reading);

  @override
  Widget build(BuildContext context) {
    Widget reading(String label, num? miles, VoidCallback? action) {
      return Expanded(
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$label: ${_text(miles)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF526071),
                  ),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 3),
                const Icon(Icons.edit_outlined,
                    color: Color(0xFF778392), size: 13),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 25,
      child: Row(
        children: [
          reading('Mi. In', mileageIn, onEditIn),
          const SizedBox(width: 7),
          const Text('│', style: TextStyle(
              fontSize: 11, color: Color(0xFF9BA5AE))),
          const SizedBox(width: 7),
          reading('Mi. Out', mileageOut, onOpenOut),
        ],
      ),
    );
  }
}
