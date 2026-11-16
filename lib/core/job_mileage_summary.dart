import 'mileage_workflow.dart';

/// One Job's intake/departure readings, without conflating legacy invoice
/// odometer_in with the explicit v2 Invoice Mileage Out field.
class JobMileageSummary {
  const JobMileageSummary._();

  static num? mileageIn(
    Map<String, dynamic>? job,
    Map<String, dynamic>? preInspection,
  ) => MileageWorkflow.parse(
    preInspection?['odometer'] ??
    job?['mileage_in'] ??
    job?['odometer_in'],
  );

  /// Trust only an invoice already associated with this exact Job and car.
  /// Unknown, legacy, cross-Job and cross-vehicle mileage is never used.
  static num? mileageOutFromInvoice(
    Map<String, dynamic>? detail, {
    required String jobId,
    required String vehicleId,
  }) {
    if (detail == null ||
        jobId.isEmpty ||
        vehicleId.isEmpty ||
        detail['kind'] != 'invoice' ||
        detail['job_id']?.toString() != jobId ||
        detail['vehicle_id']?.toString() != vehicleId ||
        (!detail.containsKey('mileage_out') &&
         detail['mileage_schema_version'] != 2)) {
      return null;
    }
    return MileageWorkflow.parse(detail['mileage_out']);
  }
}
