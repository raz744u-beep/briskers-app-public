import 'mileage_workflow.dart';

/// Preview-only projection of an explicitly saved invoice odometer reading.
/// No payment, status, backend or vehicle state is ever changed.
class InvoicePdfMileageProjection {
  const InvoicePdfMileageProjection._();

  static Map<String, dynamic> reconcile({
    required String documentId,
    required Map<String, dynamic> pdfDetail,
    required Map<String, dynamic>? visibleDetail,
  }) {
    final result = Map<String, dynamic>.from(pdfDetail);
    if (visibleDetail == null ||
        pdfDetail['kind']?.toString() != 'invoice' ||
        visibleDetail['kind']?.toString() != 'invoice' ||
        pdfDetail['id']?.toString() != documentId ||
        visibleDetail['id']?.toString() != documentId) {
      return result;
    }

    // Legacy odometer_in does not distinguish arrival/departure. Never
    // relabel it as Miles Out or import unrelated Current Miles.
    final visibleV2 = visibleDetail['mileage_schema_version'] == 2;
    final pdfVersion = pdfDetail['mileage_schema_version'];
    if (!visibleV2 || (pdfVersion != null && pdfVersion != 2)) {
      return result;
    }

    // Require exact linked Job and vehicle, not just matching customer.
    final jobId = pdfDetail['job_id']?.toString().trim() ?? '';
    final vehicleId = pdfDetail['vehicle_id']?.toString().trim() ?? '';
    if (jobId.isEmpty || vehicleId.isEmpty ||
        visibleDetail['job_id']?.toString().trim() != jobId ||
        visibleDetail['vehicle_id']?.toString().trim() != vehicleId) {
      return result;
    }

    final serverOut = MileageWorkflow.parse(result['mileage_out']);
    final displayedOut = MileageWorkflow.parse(visibleDetail['mileage_out']);
    final serverIn = MileageWorkflow.parse(result['mileage_in']);
    final displayedIn = MileageWorkflow.parse(visibleDetail['mileage_in']);
    if (serverOut != null || serverIn != null ||
        displayedOut != null || displayedIn != null) {
      // A verified server reading always has precedence over the screen.
      result['mileage_schema_version'] = 2;
      if (serverOut == null && displayedOut != null) {
        result['mileage_out'] = displayedOut;
      }
      if (serverIn == null && displayedIn != null) {
        result['mileage_in'] = displayedIn;
      }
    }
    return result;
  }
}
