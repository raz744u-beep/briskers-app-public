/// Read-only first-frame projection from an already permission-scoped Jobs
/// list row. This is not a Job Detail authorization or a write-capability
/// grant: the existing quarantine guard and authoritative local/server reads
/// must still run before any edit is enabled.
class JobDetailFirstFrame {
  static Map<String, dynamic>? fromSelectedRow(
    Map<String, dynamic>? row, {
    required String expectedJobId,
  }) {
    if (row == null || row['id']?.toString() != expectedJobId) return null;
    final employee = row['assigned_employee']?.toString().trim() ?? '';
    final employeeId = row['assigned_employee_id']?.toString().trim() ?? '';
    final position = row['assigned_position']?.toString().trim() ?? '';
    final vehicle = row['vehicle']?.toString().trim() ??
        row['vehicle_label']?.toString().trim() ?? '';
    return <String, dynamic>{
      'id': expectedJobId,
      'job_number': row['job_number'],
      'customer_id': row['customer_id'],
      'customer_name': row['customer_name'],
      'customer_problem_flag': row['customer_problem_flag'] == true,
      'vehicle_id': row['vehicle_id'],
      'vehicle': vehicle,
      'vehicle_vin': row['vehicle_vin'],
      'title': row['title'],
      'requested_work': row['requested_work'],
      'status': row['status'],
      'status_name': row['status_name'],
      'status_color': row['status_color'],
      'status_icon': row['status_icon'],
      'payment_state': row['payment_state'],
      'planned_hours': row['planned_hours'],
      'is_unassigned': employee.isEmpty,
      'assignments': employee.isEmpty ? const <Map<String, dynamic>>[] : [
        <String, dynamic>{
          'employee_id': employeeId,
          'employee_name': employee,
          'position': position,
        },
      ],
      'visits': const <dynamic>[],
      'pending_requests': const <dynamic>[],
      // No capabilities in the selected row: only the subsequent trusted
      // Job Detail fetch may grant actions based on capabilities.
      'capabilities': const <String, dynamic>{},
      '_first_frame_only': true,
    };
  }
}
