import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

class BriskersApi {
  const BriskersApi();

  Future<List<Map<String, dynamic>>> myBusinesses() async {
    final result = await supabase.rpc('briskers_my_businesses');
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<String>> myPermissions(String businessId) async {
    final result = await supabase.rpc(
      'briskers_my_permissions',
      params: {'p_business_id': businessId},
    );
    return List<dynamic>.from(result as List)
        .map((value) => value.toString())
        .toList();
  }

  Future<Map<String, dynamic>> syncPullOffice(
    String businessId, {
    int? afterCursor,
    int limit = 500,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_pull_office_v1',
      params: {
        'p_business_id': businessId,
        'p_after_cursor': afterCursor,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {
    int? afterCursor,
    int limit = 250,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_pull_jobs_v1',
      params: {
        'p_business_id': businessId,
        'p_after_cursor': afterCursor,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncSavePreInspection(
    String businessId,
    String jobId, {
    required String operationId,
    int? expectedRowVersion,
    String? notes,
    num? odometer,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_save_preinspection_v1',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_operation_id': operationId,
        'p_expected_row_version': expectedRowVersion,
        'p_notes': notes,
        'p_odometer': odometer,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncRegisterPreInspectionPhoto(
    String businessId,
    String jobId, {
    required String operationId,
    required String filename,
    required String mimeType,
    String? note,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_register_preinspection_photo_v1',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_operation_id': operationId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      await supabase.storage.from(bucket).uploadBinary(
        key,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );
    } on StorageException catch (error) {
      final status = error.statusCode?.toString();
      final message = error.message.toLowerCase();
      final alreadyExists =
          status == '409' || message.contains('already exists');
      if (!alreadyExists) rethrow;
    }

    await supabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<Map<String, dynamic>?> currentVisitSync(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_current_visit_sync_v1',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> vehicleFindingsSync(
    String businessId,
    String vehicleId, {
    bool includeResolved = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_vehicle_findings_sync_v1',
      params: {
        'p_business_id': businessId,
        'p_vehicle_id': vehicleId,
        'p_include_resolved': includeResolved,
      },
    );
    return List<dynamic>.from(result as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<Map<String, dynamic>> syncSaveWorkSummary(
    String businessId,
    String jobId, {
    required String operationId,
    required int? expectedRowVersion,
    required String workSummary,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_save_work_summary_v1',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_operation_id': operationId,
        'p_expected_row_version': expectedRowVersion,
        'p_work_summary': workSummary,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncCreateFinding(
    String businessId,
    String jobId, {
    required String operationId,
    required String body,
    bool includeOnInvoice = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_create_finding_v1',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_operation_id': operationId,
        'p_body': body,
        'p_include_on_invoice': includeOnInvoice,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncUpdateFinding(
    String businessId,
    String findingId, {
    required String operationId,
    required int? expectedRowVersion,
    required String body,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_update_finding_v1',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_operation_id': operationId,
        'p_expected_row_version': expectedRowVersion,
        'p_body': body,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncRegisterFindingPhoto(
    String businessId,
    String findingId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    final result = await supabase.rpc(
      'briskers_sync_register_finding_photo_v1',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_operation_id': operationId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> aiCommand(
    String businessId,
    String command,
  ) async {
    try {
      final result = await supabase.functions.invoke(
        'briskers-ai-command',
        body: {
          'business_id': businessId,
          'command': command,
          'local_now': DateTime.now().toIso8601String(),
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(error.reasonPhrase ?? 'Briskers AI command failed.');
    }
  }

  Future<List<DateTime>> calendarEventDays(
    String businessId,
    DateTime month,
  ) async {
    final first = DateTime(month.year, month.month, 1);
    final result = await supabase.rpc(
      'briskers_calendar_event_days',
      params: {
        'p_business_id': businessId,
        'p_month': first.toIso8601String().split('T').first,
      },
    );
    return (result as List<dynamic>)
        .map((value) => DateTime.parse(value.toString()))
        .toList();
  }

  Future<Map<String, dynamic>> navCounts(
    String businessId,
    String day,
  ) async {
    final result = await supabase.rpc(
      'briskers_nav_counts',
      params: {
        'p_business_id': businessId,
        'p_day': day,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> attentionCounts(
    String businessId,
    String day, {
    DateTime? customersSince,
  }) async {
    final result = await supabase.rpc(
      'briskers_attention_counts',
      params: {
        'p_business_id': businessId,
        'p_day': day,
        'p_customers_since': customersSince?.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> documents(
    String businessId, {
    required String kind,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_documents_v2',
      params: {
        'p_business_id': businessId,
        'p_kind': kind,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> dashboard(String businessId, String day) async {
    final result = await supabase.rpc(
      'briskers_dashboard',
      params: {'p_business_id': businessId, 'p_day': day},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<int> customerTotal(String businessId) async {
    final result = await supabase.rpc(
      'briskers_customer_total',
      params: {'p_business_id': businessId},
    );
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<List<Map<String, dynamic>>> customers(
    String businessId, {
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_customers',
      params: {
        'p_business_id': businessId,
        'p_search': search,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final rows = (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (rows.isEmpty) return rows;

    final ids = rows.map((row) => row['id']?.toString()).whereType<String>().toList();
    final flagsRaw = await supabase.rpc(
      'briskers_customer_problem_flags',
      params: {
        'p_business_id': businessId,
        'p_customer_ids': ids,
      },
    );
    final flags = <String, Map<String, dynamic>>{
      for (final raw in List<dynamic>.from(flagsRaw ?? const []))
        Map<String, dynamic>.from(raw)['customer_id'].toString():
            Map<String, dynamic>.from(raw),
    };
    for (final row in rows) {
      final flag = flags[row['id']?.toString()];
      row['problem_flag'] = flag?['problem_flag'] == true;
      row['problem_flag_note'] = flag?['problem_flag_note']?.toString() ?? '';
    }
    return rows;
  }

  Future<void> setCustomerProblemFlag(
    String businessId,
    String customerId, {
    required bool flagged,
    String? note,
  }) async {
    await supabase.rpc(
      'briskers_set_customer_problem_flag',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_flagged': flagged,
        'p_note': note,
      },
    );
  }

  Future<String> createCustomer(
    String businessId, {
    required String name,
    String? phone,
    String? email,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_customer',
      params: {
        'p_business_id': businessId,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> customerDetail(
    String businessId,
    String customerId,
  ) async {
    final result = await supabase.rpc(
      'briskers_customer_detail',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }


  Future<List<Map<String, dynamic>>> customerAppointments(
    String businessId,
    String customerId,
  ) async {
    final result = await supabase.rpc(
      'briskers_customer_appointments',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> customerServiceHistory(
    String businessId,
    String customerId,
  ) async {
    final result = await supabase.rpc(
      'briskers_customer_service_history',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>?> customerAccountContext(
    String businessId,
    String customerId,
  ) async {
    try {
      final result = await supabase.rpc(
        'briskers_customer_account_context',
        params: {
          'p_business_id': businessId,
          'p_customer_id': customerId,
        },
      );
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> customerAccountAction(
    String businessId,
    String customerId,
    String action,
  ) async {
    try {
      final result = await supabase.functions.invoke(
        'customer-account-admin',
        body: {
          'business_id': businessId,
          'customer_id': customerId,
          'action': action,
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Customer account action failed.',
      );
    }
  }

  Future<Map<String, dynamic>> updateCustomerProfile(
    String businessId,
    String customerId, {
    required String name,
    String? phone,
    String? email,
  }) async {
    try {
      final result = await supabase.functions.invoke(
        'customer-account-admin',
        body: {
          'business_id': businessId,
          'customer_id': customerId,
          'action': 'update_profile',
          'name': name,
          'phone': phone,
          'email': email,
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not update customer.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> customerNotes(
    String businessId,
    String customerId,
  ) async {
    final result = await supabase.rpc(
      'briskers_list_customer_notes',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> updateCustomerNote(
    String businessId,
    String noteId, {
    required String body,
  }) async {
    await supabase.rpc(
      'briskers_update_customer_note',
      params: {
        'p_business_id': businessId,
        'p_note_id': noteId,
        'p_body': body,
      },
    );
  }

  Future<void> deleteCustomerNote(
    String businessId,
    String noteId,
  ) async {
    try {
      await supabase.functions.invoke(
        'customer-note-admin',
        body: {
          'business_id': businessId,
          'note_id': noteId,
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not delete customer note.',
      );
    }
  }

  Future<void> deleteCustomerNoteAttachment(
    String businessId,
    String noteId,
    String attachmentId,
  ) async {
    try {
      await supabase.functions.invoke(
        'customer-note-admin',
        body: {
          'business_id': businessId,
          'note_id': noteId,
          'attachment_id': attachmentId,
          'action': 'delete_attachment',
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not remove note picture.',
      );
    }
  }

  Future<String> createCustomerNote(
    String businessId,
    String customerId, {
    String? body,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_customer_note',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_body': body,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> registerCustomerNotePhoto(
    String businessId,
    String noteId, {
    required String filename,
    required String mimeType,
  }) async {
    final result = await supabase.rpc(
      'briskers_register_customer_note_photo',
      params: {
        'p_business_id': businessId,
        'p_note_id': noteId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadCustomerNotePhoto(
    String businessId,
    String noteId, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final registration = await registerCustomerNotePhoto(
      businessId,
      noteId,
      filename: filename,
      mimeType: mimeType,
    );
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();

    await supabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await supabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<Map<String, dynamic>?> jobPreInspection(String businessId, String jobId) async {
    final result = await supabase.rpc('briskers_job_pre_inspection', params: {'p_business_id': businessId, 'p_job_id': jobId});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> saveJobPreInspection(String businessId, String jobId, {String? notes, num? odometer}) async {
    final result = await supabase.rpc('briskers_save_job_pre_inspection', params: {'p_business_id': businessId, 'p_job_id': jobId, 'p_notes': notes, 'p_odometer': odometer});
    return result.toString();
  }

  Future<void> uploadJobPreInspectionPhoto(String businessId, String jobId, {required String filename, required String mimeType, required Uint8List bytes, String? note}) async {
    final raw = await supabase.rpc('briskers_register_preinspection_photo', params: {'p_business_id': businessId, 'p_job_id': jobId, 'p_original_filename': filename, 'p_mime_type': mimeType, 'p_note': note});
    final registration = Map<String, dynamic>.from(raw as Map);
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();
    await supabase.storage.from(bucket).uploadBinary(key, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false));
    await supabase.rpc('briskers_finalize_attachment', params: {'p_business_id': businessId, 'p_attachment_id': attachmentId, 'p_byte_size': bytes.length});
  }

  Future<void> updateJobPreInspectionPhotoNote(String businessId, String photoId, String note) async {
    await supabase.rpc('briskers_update_preinspection_photo_note', params: {'p_business_id': businessId, 'p_photo_id': photoId, 'p_note': note});
  }

  Future<void> deleteJobPreInspectionPhoto(String businessId, String photoId) async {
    await supabase.rpc('briskers_delete_preinspection_photo', params: {'p_business_id': businessId, 'p_photo_id': photoId});
  }

  Future<String> signedAttachmentUrl(String bucket, String key) {
    return supabase.storage.from(bucket).createSignedUrl(key, 3600);
  }

  Future<String> createVehicle(
    String businessId,
    String customerId, {
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_vehicle_v3',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_make': make,
        'p_model': model,
        'p_year': year,
        'p_vin': vin,
        'p_license_plate': licensePlate,
        'p_license_state': licenseState,
        'p_mileage': mileage,
        'p_color': color,
      },
    );
    return result.toString();
  }

  Future<String> updateVehicle(
    String businessId,
    String vehicleId, {
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    final result = await supabase.rpc(
      'briskers_update_vehicle',
      params: {
        'p_business_id': businessId,
        'p_vehicle_id': vehicleId,
        'p_make': make,
        'p_model': model,
        'p_year': year,
        'p_vin': vin,
        'p_license_plate': licensePlate,
        'p_license_state': licenseState,
        'p_mileage': mileage,
        'p_color': color,
      },
    );
    return result.toString();
  }


  Future<Map<String, dynamic>> taxSettings(String businessId) async {
    final result = await supabase.rpc(
      'briskers_tax_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateTaxSettings(
    String businessId, {
    required num salesTaxRate,
  }) async {
    final result = await supabase.rpc(
      'briskers_update_tax_settings',
      params: {
        'p_business_id': businessId,
        'p_sales_tax_rate': salesTaxRate,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> businessSettings(String businessId) async {
    final result = await supabase.rpc(
      'briskers_business_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateBusinessSettings(
    String businessId, {
    required String name,
    String? address,
    num? latitude,
    num? longitude,
    String? operatingHours,
    String? phone,
    String? email,
    String? googleReviewsUrl,
    String? facebookPageUrl,
    String? aboutService,
  }) async {
    final result = await supabase.rpc(
      'briskers_update_business_settings',
      params: {
        'p_business_id': businessId,
        'p_name': name,
        'p_address': address,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_operating_hours': operatingHours,
        'p_phone': phone,
        'p_email': email,
        'p_google_reviews_url': googleReviewsUrl,
        'p_facebook_page_url': facebookPageUrl,
        'p_about_service': aboutService,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> employeePositions(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_employee_positions',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveEmployeePosition(
    String businessId, {
    String? positionId,
    required String name,
    required bool active,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_employee_position',
      params: {
        'p_business_id': businessId,
        'p_position_id': positionId,
        'p_name': name,
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<void> deleteEmployeePosition(
    String businessId,
    String positionId,
  ) async {
    await supabase.rpc(
      'briskers_delete_employee_position',
      params: {
        'p_business_id': businessId,
        'p_position_id': positionId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> employeesSettings(
    String businessId,
  ) async {
    final result = await supabase.rpc(
      'briskers_list_employees_settings',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> employeeSettingsDetail(
    String businessId,
    String employeeId,
  ) async {
    final result = await supabase.rpc(
      'briskers_employee_settings_detail',
      params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String?> revealEmployeeSsn(
    String businessId,
    String employeeId,
  ) async {
    final result = await supabase.rpc(
      'briskers_reveal_employee_ssn',
      params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
      },
    );
    return result?.toString();
  }

  Future<String> saveEmployeeSettings(
    String businessId, {
    String? employeeId,
    required String name,
    String? phone,
    String? email,
    String? address,
    required String positionId,
    required bool compensationEnabled,
    String? paymentType,
    num? hourlyRate,
    num? weeklyRate,
    required bool active,
    String? ssn,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_employee_settings',
      params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_position_id': positionId,
        'p_compensation_enabled': compensationEnabled,
        'p_payment_type': paymentType,
        'p_hourly_rate': hourlyRate,
        'p_weekly_rate': weeklyRate,
        'p_active': active,
        'p_ssn': ssn,
      },
    );
    return result.toString();
  }

  Future<void> deleteEmployee(
    String businessId,
    String employeeId,
  ) async {
    await supabase.rpc(
      'briskers_delete_employee',
      params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
      },
    );
  }

  Future<String> createJob(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_job',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_title': title,
        'p_description': description,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> jobDetail(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_job_detail',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> jobProfitability(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_job_profitability',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> expenseOptions(
    String businessId, {
    bool directOnly = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_expense_options',
      params: {
        'p_business_id': businessId,
        'p_direct_only': directOnly,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> transactionOptions(String businessId) async {
    final result = await supabase.rpc(
      'briskers_transaction_options',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> transactions(
    String businessId, {
    int limit = 500,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_transactions',
      params: {'p_business_id': businessId, 'p_limit': limit},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> transactionDetail(
    String businessId,
    String transactionId,
  ) async {
    final result = await supabase.rpc(
      'briskers_transaction_detail',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> createManualTransaction(
    String businessId, {
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_manual_transaction',
      params: {
        'p_business_id': businessId,
        'p_direction': direction,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_amount': amount,
        'p_date': date.toIso8601String().split('T').first,
        'p_job_id': jobId,
        'p_document_id': documentId,
        'p_counterparty_id': counterpartyId,
        'p_counterparty_name': counterpartyName,
        'p_remarks': remarks,
      },
    );
    return result.toString();
  }

  Future<void> updateManualTransaction(
    String businessId,
    String transactionId, {
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    await supabase.rpc(
      'briskers_update_manual_transaction',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_direction': direction,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_amount': amount,
        'p_date': date.toIso8601String().split('T').first,
        'p_job_id': jobId,
        'p_document_id': documentId,
        'p_counterparty_id': counterpartyId,
        'p_counterparty_name': counterpartyName,
        'p_remarks': remarks,
      },
    );
  }

  Future<void> voidManualTransaction(
    String businessId,
    String transactionId,
  ) async {
    await supabase.rpc(
      'briskers_void_manual_transaction',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
      },
    );
  }

  Future<Map<String, dynamic>> transactionSettings(String businessId) async {
    final result = await supabase.rpc(
      'briskers_transaction_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> saveTransactionCategory(
    String businessId, {
    String? categoryId,
    required String name,
    required String normalDirection,
    required bool active,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_transaction_category',
      params: {
        'p_business_id': businessId,
        'p_category_id': categoryId,
        'p_name': name,
        'p_normal_direction': normalDirection,
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<void> deleteTransactionCategory(
    String businessId,
    String categoryId,
  ) async {
    await supabase.rpc(
      'briskers_delete_transaction_category',
      params: {
        'p_business_id': businessId,
        'p_category_id': categoryId,
      },
    );
  }

  Future<String> saveCounterparty(
    String businessId, {
    String? counterpartyId,
    required String name,
    required bool active,
    String? defaultCategoryId,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_counterparty',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': counterpartyId,
        'p_name': name,
        'p_active': active,
      },
    );
    final id = result.toString();
    await supabase.rpc(
      'briskers_set_counterparty_default_category',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': id,
        'p_category_id': defaultCategoryId,
      },
    );
    return id;
  }

  Future<void> deleteCounterparty(
    String businessId,
    String counterpartyId,
  ) async {
    await supabase.rpc(
      'briskers_delete_counterparty',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': counterpartyId,
      },
    );
  }

  Future<String> saveQuickTransaction(
    String businessId, {
    String? templateId,
    required String name,
    required String direction,
    String? vendorId,
    required String accountId,
    required String categoryId,
    String? remarks,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_quick_transaction',
      params: {
        'p_business_id': businessId,
        'p_template_id': templateId,
        'p_name': name,
        'p_direction': direction,
        'p_vendor_id': vendorId,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_remarks': remarks,
        'p_sort_order': sortOrder,
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<void> deleteQuickTransaction(
    String businessId,
    String templateId,
  ) async {
    await supabase.rpc(
      'briskers_delete_quick_transaction',
      params: {
        'p_business_id': businessId,
        'p_template_id': templateId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> recurringTransactions(
    String businessId,
  ) async {
    final result = await supabase.rpc(
      'briskers_recurring_transactions',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveRecurringTransaction(
    String businessId, {
    String? ruleId,
    String? sourceTransactionId,
    required String direction,
    String? vendorId,
    required String accountId,
    required String categoryId,
    required num amount,
    String? remarks,
    required String frequency,
    required int intervalCount,
    required DateTime nextDate,
    DateTime? endDate,
    bool isRepeating = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_recurring_transaction',
      params: {
        'p_business_id': businessId,
        'p_rule_id': ruleId,
        'p_source_transaction_id': sourceTransactionId,
        'p_direction': direction,
        'p_vendor_id': vendorId,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_amount': amount,
        'p_remarks': remarks,
        'p_frequency': frequency,
        'p_interval_count': intervalCount,
        'p_next_date': nextDate.toIso8601String().split('T').first,
        'p_end_date': endDate?.toIso8601String().split('T').first,
        'p_is_repeating': isRepeating,
      },
    );
    return result.toString();
  }

  Future<void> stopRecurringTransaction(
    String businessId,
    String ruleId,
  ) async {
    await supabase.rpc(
      'briskers_stop_recurring_transaction',
      params: {'p_business_id': businessId, 'p_rule_id': ruleId},
    );
  }

  Future<Map<String, dynamic>> expenseSettings(String businessId) async {
    final result = await supabase.rpc(
      'briskers_expense_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> saveFinancialAccount(
    String businessId, {
    String? accountId,
    required String name,
    required String accountKind,
    required bool active,
    required bool isDefaultExpense,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_financial_account',
      params: {
        'p_business_id': businessId,
        'p_account_id': accountId,
        'p_name': name,
        'p_account_kind': accountKind,
        'p_active': active,
        'p_is_default_expense': isDefaultExpense,
      },
    );
    return result.toString();
  }

  Future<String> saveExpenseCategory(
    String businessId, {
    String? categoryId,
    required String name,
    required bool active,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_expense_category',
      params: {
        'p_business_id': businessId,
        'p_category_id': categoryId,
        'p_name': name,
        'p_report_treatment': 'review',
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<String> createExpense(
    String businessId, {
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? vendorName,
    String? remarks,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_expense_v2',
      params: {
        'p_business_id': businessId,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_amount': amount,
        'p_date': date.toIso8601String().split('T').first,
        'p_job_id': jobId,
        'p_document_id': documentId,
        'p_vendor_name': vendorName,
        'p_remarks': remarks,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> expenses(
    String businessId, {
    int limit = 200,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_expenses',
      params: {
        'p_business_id': businessId,
        'p_limit': limit,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> documentExpenses(
    String businessId,
    String documentId,
  ) async {
    final result = await supabase.rpc(
      'briskers_document_expenses',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> expenseDetail(
    String businessId,
    String transactionId,
  ) async {
    final result = await supabase.rpc(
      'briskers_expense_detail',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> expenseReceiptImportCandidates(
    String businessId,
  ) async {
    final result = await supabase.rpc(
      'briskers_expense_receipt_import_candidates',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> registerExpensePhoto(
    String businessId,
    String transactionId, {
    required String filename,
    required String mimeType,
  }) async {
    final result = await supabase.rpc(
      'briskers_register_expense_photo',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadExpensePhoto(
    String businessId,
    String transactionId, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final registration = await registerExpensePhoto(
      businessId,
      transactionId,
      filename: filename,
      mimeType: mimeType,
    );
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();

    await supabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await supabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<void> deleteExpensePhoto(
    String businessId,
    String transactionId,
    String attachmentId, {
    required String bucket,
    required String key,
  }) async {
    if (key.isNotEmpty) {
      await supabase.storage.from(bucket).remove([key]);
    }

    await supabase.rpc(
      'briskers_archive_expense_attachment',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_attachment_id': attachmentId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> assignableEmployees(
    String businessId,
  ) async {
    final result = await supabase.rpc(
      'briskers_assignable_employees',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> setPrimaryJobEmployee(
    String businessId,
    String jobId,
    String employeeId,
  ) async {
    await supabase.rpc(
      'briskers_set_primary_job_employee',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_employee_id': employeeId,
      },
    );
  }

  Future<void> clearJobAssignments(
    String businessId,
    String jobId,
  ) async {
    await supabase.rpc(
      'briskers_clear_job_assignments',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> jobs(
    String businessId, {
    String? status,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_jobs_v2',
      params: {
        'p_business_id': businessId,
        'p_status': status,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> jobStatuses(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_job_statuses',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> invoiceStatusStyles(
    String businessId,
  ) async {
    final result = await supabase.rpc(
      'briskers_invoice_status_styles',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveInvoiceStatusStyle(
    String businessId, {
    required String code,
    required String name,
    required String colorHex,
    required String iconKey,
    required int sortOrder,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_invoice_status_style',
      params: {
        'p_business_id': businessId,
        'p_code': code,
        'p_name': name,
        'p_color_hex': colorHex,
        'p_icon_key': iconKey,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<String> saveJobStatus(
    String businessId, {
    String? statusId,
    required String name,
    required String colorHex,
    required String iconKey,
    required bool active,
    required int sortOrder,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_job_status',
      params: {
        'p_business_id': businessId,
        'p_status_id': statusId,
        'p_name': name,
        'p_color_hex': colorHex,
        'p_icon_key': iconKey,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<void> deleteJobStatus(
    String businessId,
    String statusId,
  ) async {
    await supabase.rpc(
      'briskers_delete_job_status',
      params: {
        'p_business_id': businessId,
        'p_status_id': statusId,
      },
    );
  }

  Future<void> updateJob(
    String businessId,
    String jobId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? requestedWork,
    required num plannedHours,
  }) async {
    await supabase.rpc(
      'briskers_update_job_v2',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_title': title,
        'p_requested_work': requestedWork,
        'p_planned_hours': plannedHours,
      },
    );
  }

  Future<void> updateCurrentVisitWorkSummary(
    String businessId,
    String jobId, {
    String? workSummary,
  }) async {
    await supabase.rpc(
      'briskers_update_current_visit_work_summary',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_work_summary': workSummary,
      },
    );
  }

  Future<void> changeJobStatus(
    String businessId,
    String jobId,
    String statusCode, {
    String? note,
  }) async {
    await supabase.rpc(
      'briskers_change_job_status',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_status_code': statusCode,
        'p_note': note,
      },
    );
  }

  Future<String> requestJobAssignment(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_request_job_assignment',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return result.toString();
  }

  Future<void> decideJobAssignmentRequest(
    String businessId,
    String requestId, {
    required bool approve,
  }) async {
    await supabase.rpc(
      'briskers_decide_job_assignment_request',
      params: {
        'p_business_id': businessId,
        'p_request_id': requestId,
        'p_approve': approve,
      },
    );
  }

  Future<List<Map<String, dynamic>>> appointments(
    String businessId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await supabase.rpc(
      'briskers_list_appointments',
      params: {
        'p_business_id': businessId,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> updateAppointment(
    String businessId,
    String appointmentId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
  }) async {
    await supabase.rpc(
      'briskers_update_appointment',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_title': title,
        'p_description': description,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_employee_id': employeeId,
      },
    );
  }

  Future<void> setAppointmentStatus(
    String businessId,
    String appointmentId,
    String status,
  ) async {
    await supabase.rpc(
      'briskers_set_appointment_status',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
        'p_status': status,
      },
    );
  }

  Future<void> cancelAppointment(
    String businessId,
    String appointmentId,
  ) async {
    await supabase.rpc(
      'briskers_cancel_appointment',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
      },
    );
  }

  Future<void> deleteAppointment(
    String businessId,
    String appointmentId,
  ) async {
    await supabase.rpc(
      'briskers_delete_appointment',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
      },
    );
  }

  Future<String> createAppointment(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_appointment',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_title': title,
        'p_description': description,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_employee_id': employeeId,
      },
    );
    return result.toString();
  }

  Future<String> checkInAppointment(
    String businessId,
    String appointmentId,
  ) async {
    final result = await supabase.rpc(
      'briskers_check_in_appointment',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> vehicleFindings(
    String businessId,
    String vehicleId, {
    bool includeResolved = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_vehicle_findings',
      params: {
        'p_business_id': businessId,
        'p_vehicle_id': vehicleId,
        'p_include_resolved': includeResolved,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> createVehicleFindingForVehicle(
    String businessId,
    String customerId,
    String vehicleId, {
    required String body,
    bool includeOnInvoice = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_vehicle_finding_for_vehicle',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_body': body,
        'p_include_on_invoice': includeOnInvoice,
      },
    );
    return result.toString();
  }

  Future<void> updateVehicleFinding(
    String businessId,
    String findingId, {
    required String body,
  }) async {
    await supabase.rpc(
      'briskers_update_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_body': body,
      },
    );
  }

  Future<String> createVehicleFinding(
    String businessId,
    String jobId, {
    required String body,
    bool includeOnInvoice = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_body': body,
        'p_include_on_invoice': includeOnInvoice,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> registerVehicleFindingPhoto(
    String businessId,
    String findingId, {
    required String filename,
    required String mimeType,
  }) async {
    final result = await supabase.rpc(
      'briskers_register_finding_photo',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadVehicleFindingPhoto(
    String businessId,
    String findingId, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final registration = await registerVehicleFindingPhoto(
      businessId,
      findingId,
      filename: filename,
      mimeType: mimeType,
    );
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();

    await supabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await supabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<void> deleteVehicleFindingPhoto(
    String businessId,
    String findingId,
    String attachmentId, {
    required String bucket,
    required String key,
  }) async {
    if (key.isNotEmpty) {
      await supabase.storage.from(bucket).remove([key]);
    }

    await supabase.rpc(
      'briskers_archive_finding_attachment',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_attachment_id': attachmentId,
      },
    );
  }

  Future<void> setVehicleFindingInvoiceFlag(
    String businessId,
    String findingId,
    bool include,
  ) async {
    await supabase.rpc(
      'briskers_set_vehicle_finding_invoice_flag',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_include': include,
      },
    );
  }

  Future<void> addVehicleFindingToJob(
    String businessId,
    String findingId,
    String jobId,
  ) async {
    await supabase.rpc(
      'briskers_add_finding_to_job',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_job_id': jobId,
      },
    );
  }

  Future<void> removeVehicleFindingFromJob(
    String businessId,
    String findingId,
    String jobId,
  ) async {
    await supabase.rpc(
      'briskers_remove_finding_from_job',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_job_id': jobId,
      },
    );
  }

  Future<void> resolveVehicleFinding(
    String businessId,
    String findingId,
    String jobId,
  ) async {
    await supabase.rpc(
      'briskers_resolve_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_job_id': jobId,
      },
    );
  }

  Future<void> reopenVehicleFinding(
    String businessId,
    String findingId,
  ) async {
    await supabase.rpc(
      'briskers_reopen_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
      },
    );
  }

  Future<void> deleteVehicleFinding(
    String businessId,
    String findingId,
  ) async {
    await supabase.rpc(
      'briskers_delete_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
      },
    );
  }

  Future<String> createEstimate(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_create_estimate',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return result.toString();
  }

  Future<String> createInvoice(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_create_invoice',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return result.toString();
  }

  Future<String> convertEstimate(
    String businessId,
    String estimateId,
  ) async {
    final result = await supabase.rpc(
      'briskers_convert_estimate',
      params: {
        'p_business_id': businessId,
        'p_estimate_id': estimateId,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> jobDocuments(
    String businessId,
    String jobId,
  ) async {
    final result = await supabase.rpc(
      'briskers_job_documents',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async {
    final result = await supabase.rpc(
      'briskers_document_detail',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> itemCategories(
    String businessId, {
    bool includeInactive = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_item_categories',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveItemCategory(
    String businessId, {
    String? categoryId,
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_item_category',
      params: {
        'p_business_id': businessId,
        'p_category_id': categoryId,
        'p_name': name,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> paymentMethodsSettings(
    String businessId, {
    bool includeInactive = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_payment_methods_settings',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> savePaymentMethod(
    String businessId, {
    String? methodId,
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_payment_method',
      params: {
        'p_business_id': businessId,
        'p_method_id': methodId,
        'p_name': name,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> catalogItemsSettings(
    String businessId, {
    String? search,
    bool includeInactive = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_catalog_items_settings',
      params: {
        'p_business_id': businessId,
        'p_search': search,
        'p_include_inactive': includeInactive,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveCatalogItem(
    String businessId, {
    String? itemId,
    required String name,
    String? description,
    required String itemType,
    required num sellingPrice,
    String? pricingUnit,
    required num cost,
    required bool taxable,
    String? category,
    String? barcode,
    required bool active,
  }) async {
    final result = await supabase.rpc(
      'briskers_save_catalog_item',
      params: {
        'p_business_id': businessId,
        'p_item_id': itemId,
        'p_name': name,
        'p_description': description,
        'p_item_type': itemType,
        'p_selling_price': sellingPrice,
        'p_pricing_unit': pricingUnit,
        'p_cost': cost,
        'p_taxable': taxable,
        'p_category': category,
        'p_barcode': barcode,
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> catalogItemsForSale(
    String businessId, {
    String? search,
  }) async {
    final result = await supabase.rpc(
      'briskers_catalog_items_for_sale',
      params: {
        'p_business_id': businessId,
        'p_search': search,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> updateDocumentNotes(
    String businessId,
    String documentId, {
    required int expectedVersion,
    String? memo,
  }) async {
    await supabase.rpc(
      'briskers_update_document_notes',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_memo': memo,
      },
    );
  }

  Future<String> createQuickInvoice(
    String businessId, {
    required String customerId,
    String? vehicleId,
    DateTime? documentDate,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_quick_invoice',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_document_date': (documentDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
      },
    );
    return result.toString();
  }


  Future<String> createQuickEstimate(
    String businessId, {
    required String customerId,
    String? vehicleId,
    DateTime? documentDate,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_quick_estimate',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_document_date': (documentDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
      },
    );
    return result.toString();
  }

  Future<void> updateDocumentHeader(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required String customerId,
    String? vehicleId,
    required DateTime documentDate,
  }) async {
    await supabase.rpc(
      'briskers_update_document_header',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_document_date': documentDate.toIso8601String().split('T').first,
      },
    );
  }

  Future<void> updateDocumentMileage(
    String businessId,
    String documentId, {
    num? odometer,
  }) async {
    await supabase.rpc(
      'briskers_update_document_mileage',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_odometer': odometer,
      },
    );
  }

  Future<void> updateDocumentLineV2(
    String businessId,
    String lineId, {
    required int expectedVersion,
    required String name,
    required num quantity,
    required num unitPrice,
    required num taxRate,
    String? description,
    required String lineKind,
  }) async {
    await supabase.rpc(
      'briskers_update_document_line_v2',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_version': expectedVersion,
        'p_name': name,
        'p_quantity': quantity,
        'p_unit_price': unitPrice,
        'p_tax_rate': taxRate,
        'p_description': description,
        'p_line_kind': lineKind,
      },
    );
  }

  Future<String> copyDocumentLine(
    String businessId,
    String lineId, {
    required int expectedVersion,
  }) async {
    final result = await supabase.rpc(
      'briskers_copy_document_line',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_version': expectedVersion,
      },
    );
    return result.toString();
  }

  Future<void> moveDocumentLine(
    String businessId,
    String lineId, {
    required int expectedVersion,
    required String direction,
  }) async {
    await supabase.rpc(
      'briskers_move_document_line',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_version': expectedVersion,
        'p_direction': direction,
      },
    );
  }

  Future<String> copyInvoice(
    String businessId,
    String invoiceId, {
    bool copyNotes = false,
  }) async {
    final result = await supabase.rpc(
      'briskers_copy_invoice',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
        'p_copy_notes': copyNotes,
      },
    );
    return result.toString();
  }

  Future<void> deleteDraftInvoice(
    String businessId,
    String invoiceId,
  ) async {
    await supabase.rpc(
      'briskers_delete_draft_invoice',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
  }

  Future<void> voidInvoice(
    String businessId,
    String invoiceId,
  ) async {
    await supabase.rpc(
      'briskers_void_invoice',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
  }

  Future<String> createInvoiceFinding(
    String businessId,
    String invoiceId, {
    required String body,
    bool includeOnInvoice = true,
  }) async {
    final result = await supabase.rpc(
      'briskers_create_invoice_finding',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
        'p_body': body,
        'p_include_on_invoice': includeOnInvoice,
      },
    );
    return result.toString();
  }

  Future<void> resolveVehicleFindingByInvoice(
    String businessId,
    String findingId,
    String invoiceId,
  ) async {
    await supabase.rpc(
      'briskers_resolve_vehicle_finding_by_invoice',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
        'p_invoice_id': invoiceId,
      },
    );
  }

  Future<String> addDocumentDiscount(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required String name,
    required String method,
    required num value,
    required String timing,
    String? description,
  }) async {
    final result = await supabase.rpc(
      'briskers_add_document_discount',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_name': name,
        'p_method': method,
        'p_value': value,
        'p_timing': timing,
        'p_description': description,
      },
    );
    return result.toString();
  }

  Future<void> updateDocumentDiscount(
    String businessId,
    String lineId, {
    required int expectedVersion,
    required String name,
    required String method,
    required num value,
    required String timing,
    String? description,
  }) async {
    await supabase.rpc(
      'briskers_update_document_discount',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_version': expectedVersion,
        'p_name': name,
        'p_method': method,
        'p_value': value,
        'p_timing': timing,
        'p_description': description,
      },
    );
  }

  Future<void> addDocumentLine(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required String name,
    required num quantity,
    required num unitPrice,
    num taxRate = 0,
    String? description,
    String? itemId,
    String lineKind = 'item',
  }) async {
    await supabase.rpc(
      'briskers_add_document_line',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_document_version': expectedVersion,
        'p_name': name,
        'p_quantity': quantity,
        'p_unit_price': unitPrice,
        'p_tax_rate': taxRate,
        'p_description': description,
        'p_item_id': itemId,
        'p_line_kind': lineKind,
      },
    );
  }

  Future<void> updateDocumentLine(
    String businessId,
    String lineId, {
    required int expectedVersion,
    required num quantity,
    required num unitPrice,
    required num taxRate,
    String? description,
  }) async {
    await supabase.rpc(
      'briskers_update_document_line',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_document_version': expectedVersion,
        'p_quantity': quantity,
        'p_unit_price': unitPrice,
        'p_tax_rate': taxRate,
        'p_description': description,
      },
    );
  }

  Future<void> deleteDocumentLine(
    String businessId,
    String lineId, {
    required int expectedVersion,
  }) async {
    await supabase.rpc(
      'briskers_delete_document_line',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_expected_document_version': expectedVersion,
      },
    );
  }

  Future<String> issueDocument(
    String businessId,
    String documentId, {
    required int expectedVersion,
  }) async {
    final result = await supabase.rpc(
      'briskers_issue_document',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> paymentOptions(String businessId) async {
    final result = await supabase.rpc(
      'briskers_payment_options',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> setPendingInvoicePayment(
    String businessId,
    String invoiceId, {
    required num amount,
    required String methodId,
  }) async {
    await supabase.rpc(
      'briskers_set_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
        'p_amount': amount,
        'p_method_id': methodId,
      },
    );
  }


  Future<String> addPendingInvoicePayment(
    String businessId,
    String invoiceId, {
    required num amount,
    required String methodId,
  }) async {
    final result = await supabase.rpc(
      'briskers_add_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
        'p_amount': amount,
        'p_method_id': methodId,
      },
    );
    return result.toString();
  }

  Future<void> updatePendingInvoicePayment(
    String businessId,
    String paymentId, {
    required num amount,
    required String methodId,
  }) async {
    await supabase.rpc(
      'briskers_update_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_payment_id': paymentId,
        'p_amount': amount,
        'p_method_id': methodId,
      },
    );
  }

  Future<void> deletePendingInvoicePayment(
    String businessId,
    String paymentId,
  ) async {
    await supabase.rpc(
      'briskers_delete_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_payment_id': paymentId,
      },
    );
  }

  Future<String> finalizePendingInvoicePayment(
    String businessId,
    String invoiceId,
  ) async {
    final result = await supabase.rpc(
      'briskers_finalize_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
    return result.toString();
  }
}
