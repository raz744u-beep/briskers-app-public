import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

class BriskersApi {
  const BriskersApi();

  Future<List<Map<String, dynamic>>> myBusinesses() async {
    final result = await networkSupabase.rpc('briskers_my_businesses');
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<String>> myPermissions(String businessId) async {
    final result = await networkSupabase.rpc(
      'briskers_my_permissions',
      params: {'p_business_id': businessId},
    );
    return List<dynamic>.from(result as List)
        .map((value) => value.toString())
        .toList();
  }

  /// Lightweight, paginated and permission-checked inventory for
  /// reconciling cache IDs after a bulk legacy import.
  Future<Map<String, dynamic>> syncCacheInventory(
    String businessId, {
    required String entity,
    String? afterId,
    int limit = 250,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_cache_inventory_v1',
      params: {
        'p_business_id': businessId,
        'p_entity': entity,
        'p_after_id': afterId,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Full initial downloads use small UUID-keyset pages instead of asking
  /// PostgreSQL to build every historical job in a single statement.
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_pull_jobs_bootstrap_v2',
      params: {
        'p_business_id': businessId,
        'p_after_job_id': afterJobId,
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
      await networkSupabase.storage.from(bucket).uploadBinary(
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

    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

  Future<Map<String, dynamic>> syncPullCustomersVehicles(
    String businessId, {
    int? afterCursor,
    String? afterCustomerId,
    int limit = 250,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_pull_customers_vehicles_v1',
      params: {
        'p_business_id': businessId,
        'p_after_cursor': afterCursor,
        'p_after_customer_id': afterCustomerId,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncPullAppointments(
    String businessId, {
    int? afterCursor,
    String? afterAppointmentId,
    int limit = 250,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_pull_appointments_v1',
      params: {
        'p_business_id': businessId,
        'p_after_cursor': afterCursor,
        'p_after_appointment_id': afterAppointmentId,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncCheckInAppointment(
    String businessId,
    String appointmentId, {
    required String operationId,
    required int? expectedRowVersion,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_check_in_appointment_v1',
      params: {
        'p_business_id': businessId,
        'p_appointment_id': appointmentId,
        'p_operation_id': operationId,
        'p_expected_row_version': expectedRowVersion,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> kioskSettings(
    String businessId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_kiosk_settings_v1',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> kioskLookupCustomer(
    String businessId,
    String phone,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_kiosk_lookup_customer_v1',
      params: {
        'p_business_id': businessId,
        'p_phone': phone,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> saveKioskDisclaimer(
    String businessId,
    String disclaimerText,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_save_kiosk_disclaimer_v1',
      params: {
        'p_business_id': businessId,
        'p_disclaimer_text': disclaimerText,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> kioskRegisterWalkIn(
    String businessId, {
    required String operationId,
    required String name,
    required String phone,
    required String email,
    required int vehicleYear,
    required String vehicleMake,
    required String vehicleModel,
    required String reason,
    required bool createOnlineAccount,
    required String disclaimerId,
    required int disclaimerVersion,
    required DateTime acceptedAtDevice,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_kiosk_register_walkin_v1',
      params: {
        'p_business_id': businessId,
        'p_operation_id': operationId,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_vehicle_year': vehicleYear,
        'p_vehicle_make': vehicleMake,
        'p_vehicle_model': vehicleModel,
        'p_reason': reason,
        'p_create_online_account': createOnlineAccount,
        'p_disclaimer_id': disclaimerId,
        'p_disclaimer_version': disclaimerVersion,
        'p_accepted_at_device':
            acceptedAtDevice.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> aiCommand(
    String businessId,
    String command,
  ) async {
    try {
      final result = await networkSupabase.functions.invoke(
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

  Future<List<String>> translateManualDocumentText(
    String businessId,
    List<String> texts,
  ) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'manual-text-translate',
        body: {
          'business_id': businessId,
          'texts': texts,
        },
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      return List<dynamic>.from(data['translations'] ?? const [])
          .map((value) => value.toString())
          .toList();
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not translate document text.',
      );
    }
  }

  Future<List<DateTime>> calendarEventDays(
    String businessId,
    DateTime month,
  ) async {
    final first = DateTime(month.year, month.month, 1);
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
      'briskers_nav_counts',
      params: {
        'p_business_id': businessId,
        'p_day': day,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> needsAttention(
    String businessId, {
    int limit = 25,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_needs_attention',
      params: {
        'p_business_id': businessId,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> attentionCounts(
    String businessId,
    String day, {
    DateTime? customersSince,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_attention_counts',
      params: {
        'p_business_id': businessId,
        'p_day': day,
        'p_customers_since': customersSince?.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncPullDocuments(
    String businessId, {
    int afterVersion = 0,
    int limit = 500,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_pull_documents_v2',
      params: {
        'p_business_id': businessId,
        'p_after_version': afterVersion,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> documents(
    String businessId, {
    required String kind,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_list_documents_v4',
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
    final result = await networkSupabase.rpc(
      'briskers_dashboard',
      params: {'p_business_id': businessId, 'p_day': day},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<int> customerTotal(String businessId) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final flagsRaw = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    Map<String, dynamic>? billingAddress,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_create_customer_v2',
      params: {
        'p_business_id': businessId,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_billing_address': billingAddress ?? const <String, dynamic>{},
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> customerDetail(
    String businessId,
    String customerId,
  ) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

  Future<Map<String, dynamic>> customerFinancialHistory(
    String businessId,
    String customerId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_customer_financial_history',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>?> customerAccountContext(
    String businessId,
    String customerId,
  ) async {
    try {
      final result = await networkSupabase.rpc(
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
      final result = await networkSupabase.functions.invoke(
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
    Map<String, dynamic>? billingAddress,
  }) async {
    await networkSupabase.rpc(
      'briskers_update_customer_v2',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_billing_address': billingAddress ?? const <String, dynamic>{},
      },
    );
    return customerDetail(businessId, customerId);
  }

  Future<List<Map<String, dynamic>>> customerNotes(
    String businessId,
    String customerId,
  ) async {
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
      await networkSupabase.functions.invoke(
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
      await networkSupabase.functions.invoke(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await networkSupabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<Map<String, dynamic>?> jobPreInspection(String businessId, String jobId) async {
    final result = await networkSupabase.rpc('briskers_job_pre_inspection', params: {'p_business_id': businessId, 'p_job_id': jobId});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> saveJobPreInspection(String businessId, String jobId, {String? notes, num? odometer}) async {
    final result = await networkSupabase.rpc('briskers_save_job_pre_inspection', params: {'p_business_id': businessId, 'p_job_id': jobId, 'p_notes': notes, 'p_odometer': odometer});
    return result.toString();
  }

  Future<void> uploadJobPreInspectionPhoto(String businessId, String jobId, {required String filename, required String mimeType, required Uint8List bytes, String? note}) async {
    final raw = await networkSupabase.rpc('briskers_register_preinspection_photo', params: {'p_business_id': businessId, 'p_job_id': jobId, 'p_original_filename': filename, 'p_mime_type': mimeType, 'p_note': note});
    final registration = Map<String, dynamic>.from(raw as Map);
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();
    await networkSupabase.storage.from(bucket).uploadBinary(key, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false));
    await networkSupabase.rpc('briskers_finalize_attachment', params: {'p_business_id': businessId, 'p_attachment_id': attachmentId, 'p_byte_size': bytes.length});
  }

  Future<void> updateJobPreInspectionPhotoNote(String businessId, String photoId, String note) async {
    await networkSupabase.rpc('briskers_update_preinspection_photo_note', params: {'p_business_id': businessId, 'p_photo_id': photoId, 'p_note': note});
  }

  Future<void> deleteJobPreInspectionPhoto(String businessId, String photoId) async {
    await networkSupabase.rpc('briskers_delete_preinspection_photo', params: {'p_business_id': businessId, 'p_photo_id': photoId});
  }

  Future<String> signedAttachmentUrl(String bucket, String key) {
    return networkSupabase.storage.from(bucket).createSignedUrl(key, 3600);
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
    String? keyPassword,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_create_vehicle_v4',
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
        'p_key_password': keyPassword,
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
    String? keyPassword,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_update_vehicle_v2',
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
        'p_key_password': keyPassword,
      },
    );
    return result.toString();
  }


  Future<Map<String, dynamic>> taxSettings(String businessId) async {
    final result = await networkSupabase.rpc(
      'briskers_tax_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateTaxSettings(
    String businessId, {
    required num salesTaxRate,
    String? invoiceWarrantyMessage,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_update_tax_settings_v2',
      params: {
        'p_business_id': businessId,
        'p_sales_tax_rate': salesTaxRate,
        'p_invoice_warranty_message': invoiceWarrantyMessage,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> businessSettings(String businessId) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_delete_employee',
      params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
      },
    );
  }

  Future<Map<String, dynamic>> inviteEmployeeAppLogin(
    String businessId,
    String employeeId, {
    required String email,
  }) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'employee-account-admin',
        body: {
          'business_id': businessId,
          'employee_id': employeeId,
          'email': email.trim(),
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not create employee app login.',
      );
    }
  }

  Future<Map<String, dynamic>> createEmployeeTestLogin(
    String businessId,
    String employeeId, {
    required String email,
    required String password,
  }) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'employee-account-admin',
        body: {
          'business_id': businessId,
          'employee_id': employeeId,
          'email': email.trim(),
          'action': 'test_login',
          'password': password,
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not create test employee login.',
      );
    }
  }

  Future<String> createJob(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
  }) async {
    final result = await networkSupabase.rpc(
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

  /// Owner-only guarded deletion: fails if the Job has work or references.
  /// Owner-only preflight: current server invoices and protected Job links.
  Future<Map<String, dynamic>> jobDeletionPlan(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_job_delete_plan',
      params: {'p_business_id':businessId,'p_job_id':jobId},
    );
    return Map<String,dynamic>.from(result as Map);
  }

  /// Never silently delete paid or history-linked records.
  Future<Map<String, dynamic>> deleteJobWithUnpaidInvoices(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_delete_job_with_unpaid_v1',
      params: {'p_business_id':businessId,'p_job_id':jobId},
    );
    return Map<String,dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> deleteInvoiceManaged(
    String businessId,
    String invoiceId, {
    bool deleteJob = false,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_delete_invoice_managed_v1',
      params: {
        'p_business_id':businessId,
        'p_invoice_id':invoiceId,
        'p_with_job':deleteJob,
      },
    );
    return Map<String,dynamic>.from(result as Map);
  }

  Future<void> deleteUnusedJob(
    String businessId,
    String jobId,
  ) async {
    await networkSupabase.rpc(
      'briskers_delete_unused_job',
      params: {'p_business_id': businessId, 'p_job_id': jobId},
    );
  }

  Future<Map<String, dynamic>> jobDetail(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
      'briskers_expense_options',
      params: {
        'p_business_id': businessId,
        'p_direct_only': directOnly,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> transactionOptions(String businessId) async {
    final result = await networkSupabase.rpc(
      'briskers_transaction_options',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> expenseLinkIntegrity(
    String businessId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_expense_link_integrity',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> linkedExpensesPage(
    String businessId, {
    int limit = 500,
    int offset = 0,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_linked_expenses_page',
      params: {
        'p_business_id': businessId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Read allocation IDs in stable keyset order rather than large offsets.
  Future<List<Map<String, dynamic>>> linkedExpensesAfterPage(
    String businessId, {
    String? afterAllocationId,
    int limit = 500,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_linked_expenses_after_v1',
      params: {
        'p_business_id': businessId,
        'p_after_allocation_id': afterAllocationId,
        'p_limit': limit,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> jobLinkedExpenses(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_job_linked_expenses',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> transactions(
    String businessId, {
    int limit = 500,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_list_transactions',
      params: {'p_business_id': businessId, 'p_limit': limit},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> transactionsPaged(
    String businessId, {
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    String? direction,
    String? accountId,
    String? categoryId,
    String? counterpartyId,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_list_transactions_v2',
      params: {
        'p_business_id': businessId,
        'p_limit': limit,
        'p_offset': offset,
        'p_start_date':
            startDate?.toIso8601String().split('T').first,
        'p_end_date':
            endDate?.toIso8601String().split('T').first,
        'p_search': search,
        'p_direction': direction,
        'p_account_id': accountId,
        'p_category_id': categoryId,
        'p_counterparty_id': counterpartyId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> transactionDetail(
    String businessId,
    String transactionId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_transaction_detail',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncCreateManualTransaction(
    String businessId, {
    required String operationId,
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
    final result = await networkSupabase.rpc(
      'briskers_sync_create_manual_transaction_v1',
      params: {
        'p_business_id': businessId,
        'p_operation_id': operationId,
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
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> syncRegisterExpensePhoto(
    String businessId,
    String transactionId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_sync_register_expense_photo_v1',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_operation_id': operationId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_void_manual_transaction',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
      },
    );
  }

  Future<Map<String, dynamic>> transactionSettings(String businessId) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    num defaultSurchargePercent = 0,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_save_counterparty',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': counterpartyId,
        'p_name': name,
        'p_active': active,
      },
    );
    final id = result.toString();
    await networkSupabase.rpc(
      'briskers_set_counterparty_default_category',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': id,
        'p_category_id': defaultCategoryId,
      },
    );
    await networkSupabase.rpc(
      'briskers_set_counterparty_surcharge',
      params: {
        'p_business_id': businessId,
        'p_counterparty_id': id,
        'p_percent': defaultSurchargePercent,
      },
    );
    return id;
  }

  Future<void> deleteCounterparty(
    String businessId,
    String counterpartyId,
  ) async {
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_stop_recurring_transaction',
      params: {'p_business_id': businessId, 'p_rule_id': ruleId},
    );
  }

  Future<Map<String, dynamic>> expenseSettings(String businessId) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

  Future<void> deleteFinancialAccount(
    String businessId,
    String accountId,
  ) async {
    await networkSupabase.rpc(
      'briskers_delete_financial_account',
      params: {
        'p_business_id': businessId,
        'p_account_id': accountId,
      },
    );
  }

  Future<String> saveExpenseCategory(
    String businessId, {
    String? categoryId,
    required String name,
    required bool active,
  }) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
      'briskers_document_related_expenses_v1',
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

  /// Server-side idempotence guard for locally queued ExpenseIQ receipts.
  /// Returns transactions that already have a finalized photo attachment.
  Future<Set<String>> uploadedExpenseIqTransactions(
    String businessId,
    Iterable<String> transactionIds,
  ) async {
    final ids = transactionIds.toList();
    if (ids.isEmpty) return <String>{};
    final result = await networkSupabase.rpc(
      'briskers_expenseiq_uploaded_ids_v1',
      params: {
        'p_business_id': businessId,
        'p_transaction_ids': ids,
      },
    );
    return List<dynamic>.from(result as List)
        .map((id) => id.toString())
        .toSet();
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

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await networkSupabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<Map<String, dynamic>> parseReceiptImage(
    String businessId, {
    required Uint8List bytes,
    required String mimeType,
    String? vendorId,
  }) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'receipt-parse',
        body: {
          'business_id': businessId,
          'vendor_id': vendorId,
          'mime_type': mimeType,
          'image_base64': base64Encode(bytes),
        },
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not read receipt.',
      );
    }
  }

  Future<Map<String, dynamic>> applyExpenseReceiptExtraction(
    String businessId,
    String transactionId,
    Map<String, dynamic> extraction,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_apply_expense_receipt_extraction_v1',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_extraction': extraction,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> receiptTrainingSamples(
    String businessId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_list_receipt_training_samples_v1',
      params: {'p_business_id': businessId},
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> uploadReceiptTrainingSample(
    String businessId, {
    required String vendorId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_register_receipt_training_sample_v1',
      params: {
        'p_business_id': businessId,
        'p_vendor_id': vendorId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    final registration = Map<String, dynamic>.from(result as Map);
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await networkSupabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<void> deleteReceiptTrainingSample(
    String businessId,
    String sampleId, {
    required String bucket,
    required String key,
  }) async {
    if (key.isNotEmpty) {
      await networkSupabase.storage.from(bucket).remove([key]);
    }

    await networkSupabase.rpc(
      'briskers_delete_receipt_training_sample_v1',
      params: {
        'p_business_id': businessId,
        'p_sample_id': sampleId,
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
      await networkSupabase.storage.from(bucket).remove([key]);
    }

    await networkSupabase.rpc(
      'briskers_archive_expense_attachment',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_attachment_id': attachmentId,
      },
    );
  }

  Future<void> archiveExpensePhotoForReplace(
    String businessId,
    String transactionId,
    String attachmentId, {
    required String bucket,
    required String key,
  }) async {
    await networkSupabase.rpc(
      'briskers_archive_expense_attachment_for_replace',
      params: {
        'p_business_id': businessId,
        'p_transaction_id': transactionId,
        'p_attachment_id': attachmentId,
      },
    );

    if (key.isNotEmpty) {
      try {
        await networkSupabase.storage.from(bucket).remove([key]);
      } catch (_) {
        // The database record is already archived. Storage cleanup can retry.
      }
    }
  }

  Future<List<Map<String, dynamic>>> assignableEmployees(
    String businessId,
  ) async {
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await networkSupabase.rpc(
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
      await networkSupabase.storage.from(bucket).remove([key]);
    }

    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_delete_vehicle_finding',
      params: {
        'p_business_id': businessId,
        'p_finding_id': findingId,
      },
    );
  }

  Future<Map<String, dynamic>> parseIdentifixEstimate(
    String businessId,
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String sourceType = 'identifix',
  }) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'identifix-estimate-parse',
        body: {
          'business_id': businessId,
          'mime_type': mimeType,
          'source_type': sourceType,
          'image_base64': base64Encode(bytes),
        },
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      return Map<String, dynamic>.from(data['extraction'] as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Could not read Identifix estimate.',
      );
    }
  }

  Future<Map<String, dynamic>> createIdentifixEstimate(
    String businessId,
    String jobId,
    Map<String, dynamic> extraction, {
    String sourceType = 'identifix',
  }) async {
    final payload = Map<String, dynamic>.from(extraction)
      ..['_source_system'] =
          sourceType == 'handwritten' ? 'handwritten' : 'identifix';
    final result = await networkSupabase.rpc(
      'briskers_create_identifix_estimate',
      params: {
        'p_business_id': businessId,
        'p_job_id': jobId,
        'p_extraction': payload,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> verifyImportedPartPrice(
    String businessId, {
    required String lineId,
    required String partNumber,
    required String description,
    required String vehicle,
    required num importedUnitPrice,
  }) async {
    try {
      final result = await networkSupabase.functions.invoke(
        'part-price-verify',
        body: {
          'business_id': businessId,
          'line_id': lineId,
          'part_number': partNumber,
          'description': description,
          'vehicle': vehicle,
          'imported_unit_price': importedUnitPrice,
        },
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      return Map<String, dynamic>.from(data['verification'] as Map);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        error.reasonPhrase ?? 'Dealer price verification failed.',
      );
    }
  }

  Future<void> markImportedPartPriceReview(
    String businessId,
    String lineId, {
    required String note,
  }) async {
    await networkSupabase.rpc(
      'briskers_apply_part_price_verification',
      params: {
        'p_business_id': businessId,
        'p_line_id': lineId,
        'p_status': 'needs_review',
        'p_dealer_list_price': null,
        'p_source_name': null,
        'p_source_url': null,
        'p_note': note,
        'p_confidence': 'low',
      },
    );
  }

  Future<Map<String, dynamic>> identifixPricingStatus(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_identifix_pricing_status',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> registerDocumentSourceImage(
    String businessId,
    String documentId, {
    required String filename,
    required String mimeType,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_register_document_source_image',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_original_filename': filename,
        'p_mime_type': mimeType,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadDocumentSourceImage(
    String businessId,
    String documentId, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final registration = await registerDocumentSourceImage(
      businessId,
      documentId,
      filename: filename,
      mimeType: mimeType,
    );
    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    await networkSupabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );
  }

  Future<String> createEstimate(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
      'briskers_convert_estimate',
      params: {
        'p_business_id': businessId,
        'p_estimate_id': estimateId,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> eligibleInvoicesForEstimate(
    String businessId,
    String estimateId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_eligible_invoices_for_estimate_v1',
      params: {
        'p_business_id': businessId,
        'p_estimate_id': estimateId,
      },
    );
    return (result as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> addEstimateToExistingInvoice(
    String businessId, {
    required String estimateId,
    required String invoiceId,
    required String operationId,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_add_estimate_to_invoice_v1',
      params: {
        'p_business_id': businessId,
        'p_estimate_id': estimateId,
        'p_invoice_id': invoiceId,
        'p_operation_id': operationId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> jobDocuments(
    String businessId,
    String jobId,
  ) async {
    final result = await networkSupabase.rpc(
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

  /// Explicit, audited activation of an open/unpaid MobileBiz invoice.
  Future<void> enableImportedInvoiceEditing(
    String businessId,
    String documentId,
  ) async {
    await networkSupabase.rpc(
      'briskers_enable_open_imported_invoice_edit',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
  }

  /// Owner-only, audited override for a closed or imported invoice.
  Future<void> ownerForceReopenInvoice(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required String reason,
  }) async {
    await networkSupabase.rpc(
      'briskers_owner_force_reopen_invoice',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_document_detail_v3',
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_update_document_notes',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_memo': memo,
      },
    );
  }

  /// Upload an offline invoice atomically. Repeating the same UUID is safe.
  Future<String> syncOfflineQuickInvoice(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String documentDate,
    required List<Map<String, dynamic>> lines,
    String? memo,
  }) async {
    final id = await networkSupabase.rpc(
      'briskers_sync_offline_quick_invoice_v1',
      params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_operation_id': operationId,
        'p_document_date': documentDate,
        'p_lines': lines,
        'p_memo': memo,
      },
    );
    return id.toString();
  }

  Future<String> createQuickInvoice(
    String businessId, {
    required String customerId,
    String? vehicleId,
    DateTime? documentDate,
  }) async {
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_update_document_mileage',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_odometer': odometer,
      },
    );
  }

  Future<void> updateDocumentClaimInfo(
    String businessId,
    String documentId, {
    required int expectedVersion,
    String? claimNumber,
    String? authorizationNumber,
  }) async {
    await networkSupabase.rpc(
      'briskers_update_document_claim_info',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_claim_number': claimNumber,
        'p_authorization_number': authorizationNumber,
      },
    );
  }

  Future<Map<String, dynamic>> documentWarrantyDetail(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_document_warranty_detail',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> warrantyPaymentSettings(
    String businessId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_warranty_payment_settings',
      params: {'p_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateWarrantyPaymentSettings(
    String businessId, {
    required num cardSurchargeRate,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_update_warranty_payment_settings',
      params: {
        'p_business_id': businessId,
        'p_card_surcharge_rate': cardSurchargeRate,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> warrantyCompanies(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_warranty_companies',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return List<dynamic>.from(result as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<String> createWarrantyCompany(
    String businessId, {
    required String name,
    String? claimsPhone,
    String? submissionEmail,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_create_warranty_company',
      params: {
        'p_business_id': businessId,
        'p_name': name,
        'p_claims_phone': claimsPhone,
        'p_submission_email': submissionEmail,
      },
    );
    return result.toString();
  }

  Future<void> updateWarrantyCompany(
    String businessId,
    String companyId, {
    required String name,
    String? claimsPhone,
    String? submissionEmail,
    String? portalUrl,
    String? notes,
    bool active = true,
  }) async {
    await networkSupabase.rpc(
      'briskers_update_warranty_company',
      params: {
        'p_business_id': businessId,
        'p_company_id': companyId,
        'p_name': name,
        'p_claims_phone': claimsPhone,
        'p_submission_email': submissionEmail,
        'p_portal_url': portalUrl,
        'p_notes': notes,
        'p_active': active,
      },
    );
  }

  Future<Map<String, dynamic>> updateDocumentWarranty(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required bool extendedWarranty,
    String? warrantyCompanyId,
    String? claimNumber,
    String? authorizationNumber,
    num? approvedAmount,
    num surchargeRate = 0.03,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_update_document_warranty',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_expected_version': expectedVersion,
        'p_extended_warranty': extendedWarranty,
        'p_warranty_company_id': warrantyCompanyId,
        'p_claim_number': claimNumber,
        'p_authorization_number': authorizationNumber,
        'p_approved_amount': approvedAmount,
        'p_surcharge_rate': surchargeRate,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> documentNoteTemplates(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_document_note_templates',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return List<dynamic>.from(result as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<String> saveDocumentNoteTemplate(
    String businessId, {
    String? templateId,
    required String name,
    required String body,
    String templateType = 'standard',
    bool showInQuickList = true,
    bool active = true,
    int sortOrder = 100,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_save_document_note_template',
      params: {
        'p_business_id': businessId,
        'p_template_id': templateId,
        'p_name': name,
        'p_body': body,
        'p_template_type': templateType,
        'p_show_in_quick_list': showInQuickList,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> disclaimerTemplates(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_disclaimer_templates',
      params: {
        'p_business_id': businessId,
        'p_include_inactive': includeInactive,
      },
    );
    return List<dynamic>.from(result as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<String> saveDisclaimerTemplate(
    String businessId, {
    String? templateId,
    required String name,
    required String body,
    bool signatureRequired = true,
    bool active = true,
    int sortOrder = 100,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_save_disclaimer_template',
      params: {
        'p_business_id': businessId,
        'p_template_id': templateId,
        'p_name': name,
        'p_body': body,
        'p_signature_required': signatureRequired,
        'p_active': active,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> documentDisclaimers(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_document_disclaimers',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return List<dynamic>.from(result as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<String> saveDocumentDisclaimer(
    String businessId,
    String documentId, {
    String? disclaimerId,
    String? templateId,
    required String title,
    required String body,
    bool signatureRequired = true,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_save_document_disclaimer',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_disclaimer_id': disclaimerId,
        'p_template_id': templateId,
        'p_title': title,
        'p_body': body,
        'p_signature_required': signatureRequired,
      },
    );
    return result.toString();
  }

  Future<void> deleteDocumentDisclaimer(
    String businessId,
    String documentId,
    String disclaimerId,
  ) async {
    await networkSupabase.rpc(
      'briskers_delete_document_disclaimer',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_disclaimer_id': disclaimerId,
      },
    );
  }

  Future<Map<String, dynamic>> registerDocumentSignature(
    String businessId,
    String documentId, {
    required String signerName,
  }) async {
    final result = await networkSupabase.rpc(
      'briskers_register_document_signature',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_signer_name': signerName,
        'p_original_filename': 'customer-signature.png',
        'p_mime_type': 'image/png',
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> uploadDocumentSignature(
    String businessId,
    String documentId, {
    required String signerName,
    required Uint8List bytes,
  }) async {
    final registration = await registerDocumentSignature(
      businessId,
      documentId,
      signerName: signerName,
    );

    final bucket = registration['bucket'].toString();
    final key = registration['key'].toString();
    final attachmentId = registration['attachment_id'].toString();
    final authorizationId = registration['authorization_id'].toString();

    await networkSupabase.storage.from(bucket).uploadBinary(
      key,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/png',
        upsert: true,
      ),
    );

    await networkSupabase.rpc(
      'briskers_finalize_attachment',
      params: {
        'p_business_id': businessId,
        'p_attachment_id': attachmentId,
        'p_byte_size': bytes.length,
      },
    );

    await networkSupabase.rpc(
      'briskers_finalize_document_signature',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
        'p_authorization_id': authorizationId,
        'p_attachment_id': attachmentId,
        'p_signer_name': signerName,
      },
    );
  }

  Future<Map<String, dynamic>> documentSignatureStatus(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_document_signature_status',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> warrantySubmissionReadiness(
    String businessId,
    String documentId,
  ) async {
    final result = await networkSupabase.rpc(
      'briskers_warranty_submission_readiness',
      params: {
        'p_business_id': businessId,
        'p_document_id': documentId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Uint8List> downloadAttachment(
    String bucket,
    String key,
  ) async {
    return networkSupabase.storage.from(bucket).download(key);
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
      'briskers_delete_draft_invoice',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
  }

  Future<void> deleteEstimate(
    String businessId,
    String estimateId,
  ) async {
    await networkSupabase.rpc(
      'briskers_delete_estimate',
      params: {
        'p_business_id': businessId,
        'p_estimate_id': estimateId,
      },
    );
  }

  Future<void> voidInvoice(
    String businessId,
    String invoiceId,
  ) async {
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    await networkSupabase.rpc(
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
    final result = await networkSupabase.rpc(
      'briskers_finalize_pending_invoice_payment',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
    return result.toString();
  }

  Future<void> closeInvoice(
    String businessId,
    String invoiceId,
  ) async {
    await networkSupabase.rpc(
      'briskers_close_invoice',
      params: {
        'p_business_id': businessId,
        'p_invoice_id': invoiceId,
      },
    );
  }
}
